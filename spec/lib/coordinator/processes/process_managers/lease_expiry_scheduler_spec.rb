# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::LeaseExpiryScheduler, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
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

  it "reloads the exact UUID resource revision and turns an early execution into a typed reschedule" do
    setup_attempt
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) { reserve(duration: 30) }
    source = lifecycle_event(reservation, "ResourceLeaseAcquired")
    locator = locator_for(source)

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
    expect(lease_events(reservation).map(&:type)).to contain_exactly(
      "ResourceLeaseAcquired",
      "ResourceLeaseExpired"
    )
    expect(command_events(expiry_command_id(source)).length).to eq(1)
  end

  it "treats an acquisition timer superseded by renewal as a handled policy outcome" do
    setup_attempt
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) { reserve(duration: 30) }
    acquisition = lifecycle_event(reservation, "ResourceLeaseAcquired")
    Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 15)) { renew(reservation, duration: 60) }

    result = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 30)) do
      policy.call(locator_for(acquisition))
    end

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      class: Coordinator::Processes::LeaseExpiryHandledV1,
      outcome: "lease_observation_superseded"
    )
    expect(lease_events(reservation).none? { _1.type == "ResourceLeaseExpired" }).to be(true)
    expect(command_events(expiry_command_id(acquisition))).to be_empty
  end

  it "lets the real job reschedule an early check and complete it at the deadline" do
    setup_attempt
    reservation = Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 0)) { reserve(duration: 30) }
    source = lifecycle_event(reservation, "ResourceLeaseAcquired")
    locator = locator_for(source)
    job_scheduler

    with_real_async_jobs do
      Timecop.freeze(Time.utc(2026, 8, 22, 10, 0, 29)) do
        Coordinator::Processes::Jobs::ExpireResourceLease.perform_now(
          locator.source_event_id,
          locator.resource_stream_id,
          locator.stream_revision
        )
      end
      wait_for_expiration(reservation)
    end

    expect(lease_events(reservation).map(&:type)).to contain_exactly(
      "ResourceLeaseAcquired",
      "ResourceLeaseExpired"
    )
    expect(command_events(expiry_command_id(source)).length).to eq(1)
  end

  it "runs a past-due V2 source through one real filtered subscription and Active Job execution" do
    setup_attempt
    reservation = Timecop.freeze(Time.now.utc - 31) { reserve(duration: 30) }
    source = lifecycle_event(reservation, "ResourceLeaseAcquired")
    registration = expiry_registration
    subscription_set = build_subscription_set([ registration ])

    with_real_async_jobs do
      begin
        subscription_set.start
        wait_for_subscription(subscription_set, registration.definition.subscription_name)
        wait_for_expiration(reservation)

        expiration = lifecycle_event(reservation, "ResourceLeaseExpired")
        expect(expiration.causation_id).to eq(source.id)
        expect(expiration.correlation_id).to eq(source.correlation_id)
        expect(command_events(expiry_command_id(source)).length).to eq(1)
      ensure
        subscription_set.stop
      end
    end
  end

  it "schedules acquisition and renewal while only the current UUID lease observation expires" do
    setup_attempt
    source_time = Time.now.utc - 61
    reservation = Timecop.freeze(source_time) { reserve(duration: 30) }
    acquisition = lifecycle_event(reservation, "ResourceLeaseAcquired")
    Timecop.freeze(source_time + 15) { renew(reservation, duration: 30) }
    renewal = lifecycle_event(reservation, "ResourceLeaseRenewed")
    registration = expiry_registration
    subscription_set = build_subscription_set([ registration ])

    with_real_async_jobs do
      begin
        subscription_set.start
        wait_for_subscription(subscription_set, registration.definition.subscription_name, count: 2)
        wait_for_expiration(reservation)

        expiration = lifecycle_event(reservation, "ResourceLeaseExpired")
        expect(expiration.causation_id).to eq(renewal.id)
        expect(command_events(expiry_command_id(acquisition))).to be_empty
        expect(command_events(expiry_command_id(renewal)).length).to eq(1)
      ensure
        subscription_set.stop
      end
    end
  end

  it "accepts a non-hot V2 resource boundary through the real shared process-manager set" do
    setup_attempt
    reservation = reserve(duration: 300)
    source = lifecycle_event(reservation, "ResourceLeaseAcquired")
    registration = Coordinator::Processes::Subscriptions::ResourceBoundaryMaintenance.new(
      handler: Coordinator::Processes::ProcessManagers::ResourceBoundaryMaintenance.new(event_store:),
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

  it "stacks one four-event resource-boundary policy in that same manager" do
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

  def setup_attempt
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
  end

  def reserve(duration:)
    ResourceLeaseOperationScenario.reserve(
      event_store:,
      paths: [ "app/a.rb" ],
      command_id: "cmd-reserve-a",
      lease_duration_seconds: duration
    )
  end

  def renew(reservation, duration:)
    Coordinator::Write::Operations::ExecuteRenewLeaseSet.new(event_store:).call(
      command_id: "cmd-renew-a",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.receipt.lease_set_id,
      leases: ResourceLeaseOperationScenario.lease_inputs(reservation.receipt),
      lease_duration_seconds: duration
    ).value!
  end

  def lease_events(reservation)
    ResourceScenario.lease_events(event_store:, resource_id: reservation.resource_ids.sole)
  end

  def lifecycle_event(reservation, event_type)
    lease_events(reservation).find { _1.type == event_type }
  end

  def locator_for(event)
    Coordinator::Processes::LeaseExpirySourceLocatorV1.from_source(source_builder.call(event))
  end

  def expiry_registration
    Coordinator::Processes::Subscriptions::LeaseExpiryScheduler.new(
      handler: described_class.new(job_scheduler:),
      pull_interval: 0.2
    )
  end

  def command_events(command_id)
    event_store.read(
      Coordinator::Write::StreamFactory.new.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
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

  def wait_for_expiration(reservation)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10

    until lease_events(reservation).any? { _1.type == "ResourceLeaseExpired" }
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
