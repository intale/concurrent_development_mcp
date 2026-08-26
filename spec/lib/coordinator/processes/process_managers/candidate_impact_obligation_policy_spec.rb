# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::CandidateImpactObligationPolicy, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  let(:identities) { Coordinator::Write::CandidateObligationScans::IdentityBuilder.new }

  it "IMP-02-POLICY-LATE-01 sweeps registered surfaces and converges redelivery on one exact obligation" do
    pair = CandidateObligationScenario.submit_pair(prefix: "obligation-process-policy-late")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-process-policy-late",
      change_set_id: pair.dig(:ids, :change_set_id)
    )

    process_manager.call(policy.fetch(:partition_event))
    sweep_started = registry_sweep_events(policy).find { _1.type == "CandidateImpactRegistrySweepStarted" }
    process_manager.call(sweep_started)
    process_manager.call(sweep_started)
    drive_pair_scans(pair:, policy:)

    invocation = CandidateObligationScenario.invocation(pair:, policy:)
    obligation = CandidateObligationScenario.obligation_events(invocation.command.obligation_id).sole
    incoming_started = pair_scan_events(
      pair.dig(:target, :registration),
      "incoming",
      policy
    ).find { _1.type == "CandidateImpactPairScanStarted" }
    expect(registry_sweep_events(policy).map(&:type)).to contain_exactly(
      "CandidateImpactRegistrySweepStarted",
      "CandidateImpactRegistrySweepCompleted"
    )
    expect(obligation.causation_id).to eq(incoming_started.id)
    expect([ policy.fetch(:partition_event), sweep_started, incoming_started, obligation ].map(&:correlation_id).uniq).to eq(
      [ policy.fetch(:partition_event).correlation_id ]
    )
    expect(CandidateObligationScenario.obligation_events(invocation.command.obligation_id).length).to eq(1)
  end

  it "IMP-02-SURFACE-LATE-01 starts reciprocal scans from a registration under the current gate" do
    pair, policy = gated_pair(prefix: "obligation-process-surface-late")
    target_registration = pair.dig(:target, :registration)

    process_manager.call(target_registration)
    process_manager.call(target_registration)
    drive_pair_scans(pair:, policy:, registrations: [ target_registration ])

    invocation = CandidateObligationScenario.invocation(pair:, policy:)
    obligation = CandidateObligationScenario.obligation_events(invocation.command.obligation_id).sole
    incoming_started = pair_scan_events(target_registration, "incoming", policy).find do
      _1.type == "CandidateImpactPairScanStarted"
    end
    expect(incoming_started.causation_id).to eq(target_registration.id)
    expect(obligation.causation_id).to eq(incoming_started.id)
    expect(obligation.correlation_id).to eq(target_registration.correlation_id)
    expect(command_events(invocation.command.command_id)).to be_empty
  end

  it "runs from the real shared subscription set with one unique multi-stream registration" do
    pair = CandidateObligationScenario.submit_pair(prefix: "obligation-process-subscription")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "obligation-process-subscription",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    registration = Coordinator::Processes::Subscriptions::CandidateImpactObligationPolicy.new(
      handler: process_manager,
      pull_interval: 0.1
    )
    subscription_set = build_subscription_set([ registration ])
    invocation = CandidateObligationScenario.invocation(pair:, policy:)

    begin
      subscription_set.start
      wait_until("Candidate-obligation subscription did not converge") do
        CandidateObligationScenario.obligation_events(invocation.command.obligation_id).one?
      end
    ensure
      subscription_set.stop
    end

    expect(registration.definition.identity.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "candidate-impact-obligation-policy-v1"
    )
    expect(registration.definition.options).to eq(
      filter: {
        streams: [
          { context: "HumanGuidance", stream_name: "DecisionPartition" },
          { context: "DevelopmentIntegration", stream_name: "CandidateImpactRegistry" },
          { context: "DevelopmentIntegration", stream_name: "CandidateImpactRegistrySweep" },
          { context: "DevelopmentIntegration", stream_name: "CandidateImpactPairScan" }
        ],
        event_types: %w[
          DecisionPartitionAdvanced
          CandidateImpactSurfaceRegistered
          CandidateImpactRegistrySweepStarted
          CandidateImpactRegistrySweepProgressed
          CandidateImpactPairScanStarted
          CandidateImpactPairScanProgressed
        ]
      }
    )
  end

  def drive_pair_scans(pair:, policy:, registrations: pair.values_at(:source, :target).map { _1.fetch(:registration) })
    registrations.each do |registration|
      %w[outgoing incoming].each do |direction|
        started = pair_scan_events(registration, direction, policy).find do
          _1.type == "CandidateImpactPairScanStarted"
        end
        next unless started

        process_manager.call(started)
        process_manager.call(started)
      end
    end
  end

  def registry_sweep_events(policy)
    scan_id = identities.registry_sweep(
      policy_partition_event: reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      rule_version: Coordinator::Processes::CandidateObligations::CommandBuilder::REGISTRY_RULE_VERSION
    )
    event_store.read_grouped(
      streams.candidate_impact_registry_sweep(scan_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_REGISTRY_SWEEP_STATE
    )
  end

  def pair_scan_events(registration, direction, policy)
    scan_id = identities.pair_scan(
      source_registration: reference(registration),
      direction:,
      policy_partition_event: reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      rule_version: Coordinator::Processes::CandidateObligations::CommandBuilder::PAIR_RULE_VERSION
    )
    event_store.read_grouped(
      streams.candidate_impact_pair_scan(scan_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_STATE
    )
  end

  def gated_pair(prefix:)
    ids = {
      change_set_id: "CS-#{prefix}",
      work_item_id: "W-#{prefix}",
      attempt_id: "A-#{prefix}"
    }
    CandidateScenario.seed_attempt(ids:, agent_id: "agent-a")
    reservation = CandidateObligationScenario.execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "seed-reserve-#{prefix}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: %w[Gemfile.lock app/services/checkout.rb].map do |path|
        { kind: "file", path:, base_blob_oid: "c" * 40 }
      end,
      lease_duration_seconds: 900
    }).data
    source = CandidateObligationScenario.submit_candidate(
      prefix:,
      role: "source",
      ids:,
      reservation:,
      path: "Gemfile.lock",
      head_commit_oid: CandidateObligationScenario.head_oid(prefix, "source"),
      build_context_path: nil,
      surface: {
        produces: [ { impact_key: "dependency:rubygems:rails", before: "4.2", after: "5.0" } ],
        consumes: [],
        may_affect: [],
        assumes: []
      }
    )
    policy = CandidateObligationScenario.activate_policy(prefix:, change_set_id: ids.fetch(:change_set_id))
    target = CandidateObligationScenario.submit_candidate(
      prefix:,
      role: "target",
      ids:,
      reservation:,
      path: "app/services/checkout.rb",
      head_commit_oid: CandidateObligationScenario.head_oid(prefix, "target"),
      build_context_path: "Gemfile.lock",
      surface: {
        produces: [],
        consumes: [],
        may_affect: [],
        assumes: [ { impact_key: "dependency:rubygems:rails", predicate: "4.2 remains compatible" } ]
      }
    )
    registrations = CandidateObligationScenario.registry_events(ids.fetch(:change_set_id))
    pair = {
      ids:,
      source: source.merge(registration: CandidateObligationScenario.registration_for(registrations, source.fetch(:candidate_id))),
      target: target.merge(registration: CandidateObligationScenario.registration_for(registrations, target.fetch(:candidate_id)))
    }
    [ pair, policy ]
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def reference(event)
    Coordinator::Processes::CandidateObligations::EventReferenceBuilder.new.call(event)
  end

  def build_subscription_set(registrations)
    manager = PgEventstore.subscriptions_manager(
      subscription_set: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME
    )
    Coordinator::Processes::Subscriptions::ProcessManagerSet.new(manager:, registrations:)
  end

  def wait_until(message)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    until yield
      raise message if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end
end
