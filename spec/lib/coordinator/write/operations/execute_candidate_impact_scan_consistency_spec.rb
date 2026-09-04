# frozen_string_literal: true

RSpec.describe "Candidate impact scan start consistency", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:source_builder) { Coordinator::Processes::CandidateObligations::SourceBuilder.new(event_store:) }
  let(:policy_observer) { Coordinator::Processes::CandidateObligations::PolicyObserver.new(event_store:) }
  let(:command_builder) { Coordinator::Processes::CandidateObligations::CommandBuilder.new(event_store:) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }

  it "AUD-SCAN-POLICY-RACE-01 freezes a serializable policy decision when policy changes concurrently" do
    prime_policy_correction_partition
    pair = CandidateObligationScenario.submit_pair(prefix: "scan-policy-race")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "scan-policy-race",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = pair_start_invocation(pair:, policy:)
    corrected = nil

    result = during_boundary(
      Coordinator::Write::Operations::ExecuteStartCandidateImpactPairScan::CONSISTENCY_BOUNDARY,
      invocation.command.command_id,
      mutation: lambda do
        corrected = Thread.new do
          CandidateObligationScenario.correct_policy(
            policy:,
            prefix: "scan-policy-race",
            change_set_id: pair.dig(:ids, :change_set_id)
          )
        end.value
      end
    ) do
      Coordinator::Write::Operations::ExecuteStartCandidateImpactPairScan.new(event_store:).call(invocation)
    end

    expect(result).to be_success
    persisted = pair_scan_events(invocation.command.scan_id).sole
    payload = load(persisted)
    snapshot = Coordinator::Write::CandidateObligationScans::PairScanLoader.new(event_store:).call(
      invocation.command.scan_id
    )
    expect(snapshot.state.policy_partition_event).to eq(reference(policy.fetch(:partition_event)))
    expect(snapshot.state.policy_head).to eq(policy.fetch(:head))
    expect(reference(corrected.fetch(:partition_event))).not_to eq(snapshot.state.policy_partition_event)
    expect(current_partition(pair.dig(:ids, :change_set_id))).to eq(
      reference(corrected.fetch(:partition_event))
    )
    serialized_before_change = persisted.global_position < corrected.fetch(:partition_event).global_position
    typed_stale_denial = persisted.type == "CandidateImpactPairScanSkipped" &&
                         payload.reason == "stale_policy"
    expect(serialized_before_change || typed_stale_denial).to eq(true)
  end

  it "AUD-SCAN-REGISTRY-RACE-02 freezes a valid registry prefix when registration changes concurrently" do
    pair = CandidateObligationScenario.submit_pair(prefix: "scan-registry-race")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "scan-registry-race",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = registry_start_invocation(policy)
    pending_candidate = prepare_additional_candidate(pair)
    registration = nil

    result = during_boundary(
      Coordinator::Write::Operations::ExecuteStartCandidateImpactRegistrySweep::CONSISTENCY_BOUNDARY,
      invocation.command.command_id,
      mutation: lambda do
        Thread.new do
          CandidateScenario.submit_impact(
            pending_candidate,
            command_id: "cmd-impact-scan-registry-race-extra"
          )
          registration = CandidateObligationScenario.registry_events(
            pair.dig(:ids, :change_set_id)
          ).find { _1.data.fetch("candidate_id") == pending_candidate.dig(:input, :candidate_id) }
        end.value
      end
    ) do
      Coordinator::Write::Operations::ExecuteStartCandidateImpactRegistrySweep.new(event_store:).call(invocation)
    end

    expect(result).to be_success
    persisted = registry_sweep_events(invocation.command.scan_id).sole
    payload = load(persisted)
    expect(registration).not_to be_nil
    valid_prefix = registration.global_position > persisted.global_position ||
                   registration.global_position <= payload.to_revision
    expect(valid_prefix).to eq(true)
  end

  it "AUD-SCAN-REPLAY-03 converges concurrent duplicate starts on one logical scan" do
    pair = CandidateObligationScenario.submit_pair(prefix: "scan-replay")
    policy = CandidateObligationScenario.activate_policy(
      prefix: "scan-replay",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    invocation = pair_start_invocation(pair:, policy:)

    results = Array.new(2) do
      Thread.new do
        Coordinator::Write::Operations::ExecuteStartCandidateImpactPairScan.new(event_store:).call(invocation)
      end
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.select(&:failure?).sole.failure.code).to eq(
      :candidate_impact_pair_scan_already_decided
    )
    expect(pair_scan_events(invocation.command.scan_id).length).to eq(1)
  end

  def during_boundary(operation, command_id, mutation:)
    mutex = Thread::Mutex.new
    exercised = false
    subscriber = ActiveSupport::Notifications.subscribe(
      "coordinator.command_boundary"
    ) do |_name, _start, _finish, _id, payload|
      next unless payload.fetch(:operation) == operation
      next unless payload.fetch(:command_id) == command_id

      run = mutex.synchronize do
        next false if exercised

        exercised = true
      end
      mutation.call if run
    end
    yield
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def registry_start_invocation(policy)
    source = source_builder.call(policy.fetch(:partition_event))
    trigger = policy_observer.from_partition(source)
    command_builder.registry_start(trigger:, source:)
  end

  def pair_start_invocation(pair:, policy:)
    registration = pair.dig(:target, :registration)
    source = source_builder.call(registration)
    trigger = Coordinator::Processes::CandidateObligations::PolicyTriggerV1.new(
      change_set_id: pair.dig(:ids, :change_set_id),
      partition_event: reference(policy.fetch(:partition_event)),
      head: policy.fetch(:head)
    )
    command_builder.pair_start(
      registration:,
      direction: "incoming",
      trigger:,
      caused_by: source
    )
  end

  def prepare_additional_candidate(pair)
    ids = pair.fetch(:ids)
    reservation = pair.dig(:source, :reservation)
    input = CandidateScenario.input(
      prefix: "scan-registry-race-extra",
      ids:,
      reservation:,
      path: "Gemfile.lock",
      agent_id: "agent-a",
      candidate_id: "CAN-extra-scan-registry-race",
      command_id: "cmd-candidate-scan-registry-race-extra",
      head_commit_oid: CandidateObligationScenario.head_oid("scan-registry-race", "extra")
    ).merge(build_context: CandidateScenario.build_context_for("Gemfile.lock"))
    CandidateObligationScenario.execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    {
      input:,
      events: CandidateScenario.candidate_events(input.fetch(:candidate_id)),
      reservation:
    }
  end

  def prime_policy_correction_partition
    pair = CandidateObligationScenario.submit_pair(
      prefix: "scan-policy-race-prime",
      source_path: "prime/Gemfile.lock",
      target_path: "prime/app/services/checkout.rb"
    )
    policy = CandidateObligationScenario.activate_policy(
      prefix: "scan-policy-race-prime",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
    CandidateObligationScenario.correct_policy(
      policy:,
      prefix: "scan-policy-race-prime",
      change_set_id: pair.dig(:ids, :change_set_id)
    )
  end

  def registry_sweep_events(scan_id)
    event_store.read_grouped(
      streams.candidate_impact_registry_sweep(scan_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_REGISTRY_SWEEP_STATE
    )
  end

  def pair_scan_events(scan_id)
    event_store.read_grouped(
      streams.candidate_impact_pair_scan(scan_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_STATE
    )
  end

  def current_partition(change_set_id)
    event = event_store.read_grouped(
      streams.decision_partition("changeset:#{change_set_id}:candidate"),
      Coordinator::Write::EventQueries::DECISION_PARTITION_LATEST
    ).first
    reference(event)
  end

  def load(event)
    schemas.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end
end
