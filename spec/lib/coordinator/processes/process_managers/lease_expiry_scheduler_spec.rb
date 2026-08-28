# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::LeaseExpiryScheduler, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:normalizer) { Coordinator::Write::FileResourceNormalizer.new }
  let(:repository_id) { RepositoryScenario::DEFAULT_REPOSITORY_ID }
  let(:source_builder) { Coordinator::Processes::LeaseExpirySourceBuilder.new }
  let(:source_loader) do
    Coordinator::Processes::LeaseExpirySourceLoader.new(event_store:, source_builder:)
  end
  let(:policy) do
    Coordinator::Processes::LeaseExpiryPolicy.new(
      source_loader:,
      operation: Coordinator::Write::Operations::ExecuteExpireResourceLease.new(event_store:)
    )
  end
  let(:job_scheduler) { Coordinator::Processes::LeaseExpiryJobScheduler.new(policy:) }

  it "reloads the exact source revision and turns an early execution into a typed reschedule" do
    seed_active_attempt
    source = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(duration: 30).value!
      lease_events.sole
    end
    locator = Coordinator::Processes::LeaseExpirySourceLocatorV1.from_source(source_builder.call(source))

    early = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 29)) { policy.call(locator) }
    due = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) { policy.call(locator) }

    expect(early).to be_success
    expect(early.value!).to have_attributes(
      class: Coordinator::Processes::LeaseExpiryRescheduleV1,
      reschedule_at: "2026-08-22T10:00:30.000000Z"
    )
    expect(due).to be_success
    expect(due.value!).to have_attributes(
      class: Coordinator::Processes::LeaseExpiryHandledV1,
      outcome: "expired_or_replayed"
    )
    expect(lease_events.map(&:type)).to eq([ "ResourceLeaseAcquired", "ResourceLeaseExpired" ])
    expect(command_events(expiry_command_id(source)).length).to eq(1)
  end

  it "treats an acquisition timer superseded by renewal as a handled policy outcome" do
    seed_active_attempt
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(duration: 30).value!.data
    end
    acquisition = lease_events.sole
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 15)) do
      renew(reservation:, duration: 60).value!
    end
    locator = Coordinator::Processes::LeaseExpirySourceLocatorV1.from_source(source_builder.call(acquisition))

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) { policy.call(locator) }

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      class: Coordinator::Processes::LeaseExpiryHandledV1,
      outcome: "lease_observation_superseded"
    )
    expect(lease_events.none? { _1.type == "ResourceLeaseExpired" }).to be(true)
    expect(command_events(expiry_command_id(acquisition))).to be_empty
  end

  it "lets the real job reschedule an early check and complete it at the deadline" do
    seed_active_attempt
    source = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) do
      reserve(duration: 30).value!
      lease_events.sole
    end
    locator = Coordinator::Processes::LeaseExpirySourceLocatorV1.from_source(source_builder.call(source))
    job_scheduler

    with_real_async_jobs do
      Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 29)) do
        Coordinator::Processes::Jobs::ExpireResourceLease.perform_now(
          locator.source_event_id,
          locator.resource_key_hash,
          locator.stream_revision
        )
      end
      wait_for_expiration
    end

    expect(lease_events.map(&:type)).to eq([ "ResourceLeaseAcquired", "ResourceLeaseExpired" ])
    expect(command_events(expiry_command_id(source)).length).to eq(1)
  end

  it "runs a past-due source through one real filtered subscription and Active Job execution" do
    seed_active_attempt
    source_time = Time.now.utc - 31
    source = Timecop.freeze(source_time) do
      reserve(duration: 30).value!
      lease_events.sole
    end
    registration = Coordinator::Processes::Subscriptions::LeaseExpiryScheduler.new(
      handler: described_class.new(job_scheduler:),
      pull_interval: 0.2
    )
    subscription_set = build_subscription_set([ registration ])

    with_real_async_jobs do
      begin
        subscription_set.start
        wait_for_subscription(subscription_set, registration.definition.subscription_name)
        wait_for_expiration

        expiration = lease_events.last
        expect(expiration.type).to eq("ResourceLeaseExpired")
        expect(expiration.causation_id).to eq(source.id)
        expect(expiration.correlation_id).to eq(source.correlation_id)
        expect(command_events(expiry_command_id(source)).length).to eq(1)
      ensure
        subscription_set.stop
      end
    end
  end

  it "schedules both lifecycle source types while only the renewed observation expires" do
    seed_active_attempt
    source_time = Time.now.utc - 61
    reservation = Timecop.freeze(source_time) { reserve(duration: 30).value!.data }
    acquisition = lease_events.sole
    Timecop.freeze(source_time + 15) do
      renew(reservation:, duration: 30).value!
    end
    renewal = lease_events.last
    registration = Coordinator::Processes::Subscriptions::LeaseExpiryScheduler.new(
      handler: described_class.new(job_scheduler:),
      pull_interval: 0.2
    )
    subscription_set = build_subscription_set([ registration ])

    with_real_async_jobs do
      begin
        subscription_set.start
        wait_for_subscription(subscription_set, registration.definition.subscription_name, count: 2)
        wait_for_expiration

        expiration = lease_events.last
        expect(expiration.type).to eq("ResourceLeaseExpired")
        expect(expiration.causation_id).to eq(renewal.id)
        expect(command_events(expiry_command_id(acquisition))).to be_empty
        expect(command_events(expiry_command_id(renewal)).length).to eq(1)
      ensure
        subscription_set.stop
      end
    end
  end

  it "accepts a non-hot resource boundary through the real shared process-manager set" do
    seed_active_attempt
    reserve(duration: 300).value!
    source = lease_events.sole
    registration = Coordinator::Processes::Subscriptions::ResourceBoundaryMaintenance.new(
      handler: Coordinator::Processes::ProcessManagers::ResourceBoundaryMaintenance.new(
        event_store:
      ),
      pull_interval: 0.2
    )
    subscription_set = build_subscription_set([ registration ])

    begin
      subscription_set.start
      wait_for_subscription(subscription_set, registration.definition.subscription_name)
    ensure
      subscription_set.stop
    end

    expect(command_events(maintenance_command_id(source))).to be_empty
    expect(subscription_set.processed_event_count(registration.definition.subscription_name)).to eq(1)
  end

  it "publishes one unique multi-event registration in the shared process-manager set" do
    definition = Coordinator::Processes::Subscriptions::LeaseExpiryScheduler::DEFINITION

    expect(definition.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "lease-expiry-scheduler-v1",
      stream_context: "DevelopmentCoordination",
      stream_name: "ResourceLease",
      event_types: [ "ResourceLeaseAcquired", "ResourceLeaseRenewed" ],
      event_markers: []
    )
    expect(definition.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentCoordination", stream_name: "ResourceLease" } ],
        event_types: [ "ResourceLeaseAcquired", "ResourceLeaseRenewed" ]
      }
    )
    expect(Coordinator::Container["subscription_sets.process_managers"].subscription_names).to eq(
      [
        "agent-choice-decision-impact-v1",
        "build-progress-v1",
        "candidate-impact-obligation-policy-v1",
        "change-set-readiness-v1",
        "coordination-task-executor-lane-0-v2",
        "coordination-task-executor-lane-1-v2",
        "lease-expiry-scheduler-v1",
        "operation-batch-runner-v1",
        "release-set-lifecycle-v1",
        "resource-boundary-maintenance-v1",
        "verification-obligation-validity-v1"
      ]
    )
  end

  it "stacks one four-event resource-boundary maintenance policy in that same manager" do
    definition = Coordinator::Processes::Subscriptions::ResourceBoundaryMaintenance::DEFINITION

    expect(definition.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "resource-boundary-maintenance-v1",
      stream_context: "DevelopmentCoordination",
      stream_name: "ResourceLease",
      event_types: %w[
        ResourceLeaseAcquired
        ResourceLeaseRenewed
        ResourceLeaseReleased
        ResourceLeaseExpired
      ],
      event_markers: []
    )
    expect(Coordinator::Container["process_managers.resource_boundary_maintenance"]).to be_a(
      Coordinator::Processes::ProcessManagers::ResourceBoundaryMaintenance
    )
  end

  private

  def reserve(duration:)
    Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "cmd-reserve-a",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id:,
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: "app/a.rb" } ],
      lease_duration_seconds: duration
    )
  end

  def renew(reservation:, duration:)
    Coordinator::Write::Operations::ExecuteRenewLeaseSet.new(event_store:).call(
      command_id: "cmd-renew-a",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end,
      lease_duration_seconds: duration
    )
  end

  def seed_active_attempt
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE",
      goal: "Coordinate resource leases",
      acceptance_criteria: [ "Expired resources remain available" ]
    ).value!
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-W-LSE-A",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      repository_id:,
      goal: "Implement the lease holder",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE"
    ).value!
    activation = event_store.read(
      streams.change_set("CS-LSE"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "seed-acquire-A-LSE-A",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
    ).value!
  end

  def lease_events
    resource = normalizer.call(
      repository_id:,
      kind: "file",
      path: "app/a.rb",
      base_blob_oid: nil,
      scope: RepositoryScenario::DEFAULT_SCOPE
    ).value!
    event_store.read(
      streams.resource_lease(resource.resource_key_hash),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [
          "ResourceLeaseAcquired",
          "ResourceLeaseRenewed",
          "ResourceLeaseReleased",
          "ResourceLeaseExpired"
        ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def expiry_command_id(event)
    "#{Coordinator::Processes::LeaseExpiryCommandBuilder::COMMAND_ID_PREFIX}#{event.id}"
  end

  def maintenance_command_id(event)
    marker = Coordinator::Write::RepositoryMarkerBuilder.new.resource_event_markers(
      repository_id: event.data.fetch("repository_id"),
      resource_kind: event.data.fetch("resource_kind"),
      resource_path: event.data.fetch("resource_path")
    ).sort_by(&:b).first
    Coordinator::Processes::InternalCommandIdBuilder.call(
      "resource-boundary-rollover:v1:#{event.id}:#{marker.split(':').last}"
    )
  end

  def build_subscription_set(registrations)
    manager = PgEventstore.subscriptions_manager(
      subscription_set: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME
    )
    Coordinator::Processes::Subscriptions::ProcessManagerSet.new(manager:, registrations:)
  end

  def wait_for_subscription(subscription_set, subscription_name, count: 1)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10

    until subscription_set.processed_event_count(subscription_name) >= count
      raise "#{subscription_name} did not process the source within 10 seconds" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end

  def wait_for_expiration
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10

    until lease_events.any? { _1.type == "ResourceLeaseExpired" }
      raise "lease-expiry job did not append its fact within 10 seconds" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end

  def with_real_async_jobs
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :async
    async_adapter = ActiveJob::Base.queue_adapter
    yield
  ensure
    async_adapter&.shutdown
    ActiveJob::Base.queue_adapter = previous_adapter
  end
end
