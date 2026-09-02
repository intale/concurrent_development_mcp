# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::CandidateImpactObligationPolicy, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }

  it "IMP-02-POLICY-LATE-01 AUD-SCAN-REPLAY-03 converges duplicate delivery on one scan and obligation" do
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

    obligation = obligation_event(pair, policy)
    incoming_started = pair_scan_events(
      pair.dig(:target, :registration),
      "incoming",
      policy
    ).find { _1.type == "CandidateImpactPairScanStarted" }
    expect(registry_sweep_events(policy).map(&:type)).to contain_exactly(
      "CandidateImpactRegistrySweepStarted",
      "CandidateImpactRegistrySweepCompleted"
    )
    obligation_step = process_step(
      source_event: incoming_started,
      step_name: "create-compatibility-obligation",
      subject_kind: "candidate-registration-pair",
      subject_id: "#{pair.dig(:source, :registration).id}:#{pair.dig(:target, :registration).id}"
    )
    expect(obligation.causation_id).to eq(obligation_step.id)
    expect([ policy.fetch(:partition_event), sweep_started, incoming_started, obligation ].map(&:correlation_id).uniq).to eq(
      [ policy.fetch(:partition_event).correlation_id ]
    )
    expect(CandidateObligationScenario.obligation_events(obligation.stream.stream_id).length).to eq(1)
  end

  it "IMP-02-SURFACE-LATE-01 starts reciprocal scans from a registration under the current gate" do
    pair, policy = gated_pair(prefix: "obligation-process-surface-late")
    target_registration = pair.dig(:target, :registration)

    process_manager.call(target_registration)
    process_manager.call(target_registration)
    drive_pair_scans(pair:, policy:, registrations: [ target_registration ])

    obligation = obligation_event(pair, policy)
    incoming_started = pair_scan_events(target_registration, "incoming", policy).find do
      _1.type == "CandidateImpactPairScanStarted"
    end
    pair_step = process_step(
      source_event: target_registration,
      step_name: "start-incoming-pair-scan",
      subject_kind: "candidate-impact-registration",
      subject_id: target_registration.id
    )
    obligation_step = process_step(
      source_event: incoming_started,
      step_name: "create-compatibility-obligation",
      subject_kind: "candidate-registration-pair",
      subject_id: "#{pair.dig(:source, :registration).id}:#{pair.dig(:target, :registration).id}"
    )
    expect(incoming_started.causation_id).to eq(pair_step.id)
    expect(obligation.causation_id).to eq(obligation_step.id)
    expect(obligation.correlation_id).to eq(target_registration.correlation_id)
    expect(command_events(obligation.metadata.fetch("command_id"))).to be_empty
  end

  it "publishes one unique multi-stream registration in the shared process-manager set" do
    definition = Coordinator::Processes::Subscriptions::CandidateImpactObligationPolicy::DEFINITION

    expect(definition.identity.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "candidate-impact-obligation-policy-v1"
    )
    expect(definition.options).to eq(
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
    started = event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "DevelopmentIntegration",
        stream_name: "CandidateImpactRegistrySweep",
        event_types: [ "CandidateImpactRegistrySweepStarted" ],
        markers: [ "policy-partition-event:#{policy.fetch(:partition_event).id}" ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
    event_store.read_grouped(
      streams.candidate_impact_registry_sweep(started.stream.stream_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_REGISTRY_SWEEP_STATE
    )
  end

  def pair_scan_events(registration, direction, policy)
    started = event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "DevelopmentIntegration",
        stream_name: "CandidateImpactPairScan",
        event_types: [ "CandidateImpactPairScanStarted" ],
        markers: [ "source-registration:#{registration.id}" ],
        maximum_count: 2,
        direction: :asc
      )
    ).find { payload(_1).direction == direction }
    return [] unless started

    event_store.read_grouped(
      streams.candidate_impact_pair_scan(started.stream.stream_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_STATE
    )
  end

  def obligation_event(pair, policy)
    loader = Coordinator::Write::CandidateObligations::CandidateEvidenceLoader.new(event_store:)
    source = loader.call(reference(pair.dig(:source, :registration)))
    target = loader.call(reference(pair.dig(:target, :registration)))
    natural_key = Coordinator::Write::CandidateObligations::NaturalKeyBuilder.new.call(
      source:,
      target:,
      policy_partition_event: reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      rule_version: Coordinator::Processes::CandidateObligations::CommandBuilder::OBLIGATION_RULE_VERSION
    )
    Coordinator::Write::CandidateObligations::ObligationLoader.new(event_store:).find(natural_key).event
  end

  def payload(event)
    schemas.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def process_step(source_event:, step_name:, subject_kind:, subject_id:)
    ProcessStepExamples.event(
      event_store:,
      source_event:,
      process_name: "candidate-impact-obligation-policy",
      step_name:,
      subject_kind:,
      subject_id:
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
        ResourceScenario.target(
          event_store:,
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
          kind: "file",
          path:,
          base_blob_oid: "c" * 40
        )
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
end
