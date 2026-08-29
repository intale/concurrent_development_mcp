# frozen_string_literal: true

module CandidateObligationScenario
  module_function

  RULE_VERSION = "candidate-compatibility-obligation/v1"

  def create_obligation(
    prefix:,
    level: "merge_gate",
    required_evidence: nil,
    source_path: "Gemfile.lock",
    target_path: "app/services/checkout.rb",
    separate_work_items: false
  )
    pair = submit_pair(prefix:, source_path:, target_path:, separate_work_items:)
    policy_arguments = {
      prefix:,
      change_set_id: pair.dig(:ids, :change_set_id),
      level:
    }
    policy_arguments[:required_evidence] = required_evidence if required_evidence
    policy = activate_policy(**policy_arguments)
    result = execute(
      Coordinator::Write::Operations::ExecuteCreateCandidateCompatibilityObligation,
      invocation(pair:, policy:)
    )
    event = obligation_events(result.obligation_id).sole
    { pair:, policy:, result:, event:, payload: load(event) }
  end

  def submit_pair(
    prefix:,
    source_path: "Gemfile.lock",
    target_path: "app/services/checkout.rb",
    observed_source: true,
    source_key: "dependency:rubygems:rails",
    target_key: "dependency:rubygems:rails",
    separate_work_items: false
  )
    if separate_work_items
      return submit_separate_pair(
        prefix:,
        source_path:,
        target_path:,
        observed_source:,
        source_key:,
        target_key:
      )
    end

    ids = {
      change_set_id: "CS-#{prefix}",
      work_item_id: "W-#{prefix}",
      attempt_id: "A-#{prefix}"
    }
    CandidateScenario.seed_attempt(ids:, agent_id: "agent-a")
    reservation = execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "seed-reserve-#{prefix}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ source_path, target_path ].uniq.map do |path|
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
    source = submit_candidate(
      prefix:,
      role: "source",
      ids:,
      reservation:,
      path: source_path,
      head_commit_oid: head_oid(prefix, "source"),
      build_context_path: nil,
      surface: {
        produces: [ { impact_key: source_key, before: "4.2", after: "5.0" } ],
        consumes: [],
        may_affect: [],
        assumes: []
      }
    )
    target = submit_candidate(
      prefix:,
      role: "target",
      ids:,
      reservation:,
      path: target_path,
      head_commit_oid: head_oid(prefix, "target"),
      build_context_path: observed_source ? source_path : nil,
      surface: {
        produces: [],
        consumes: [],
        may_affect: [],
        assumes: [ { impact_key: target_key, predicate: "4.2 remains compatible" } ]
      }
    )
    registrations = registry_events(ids.fetch(:change_set_id))

    {
      ids:,
      source: source.merge(registration: registration_for(registrations, source.fetch(:candidate_id))),
      target: target.merge(registration: registration_for(registrations, target.fetch(:candidate_id)))
    }
  end

  def submit_separate_pair(prefix:, source_path:, target_path:, observed_source:, source_key:, target_key:)
    change_set_id = "CS-#{prefix}"
    RepositoryScenario.register(event_store:)
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "seed-create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate Candidate compatibility",
      acceptance_criteria: [ "Both Candidate results are attributable" ]
    })
    source_ids = seed_pair_attempt(
      prefix:,
      role: "source",
      change_set_id:,
      path: source_path
    )
    target_ids = seed_pair_attempt(
      prefix:,
      role: "target",
      change_set_id:,
      path: target_path
    )
    activate_pair(change_set_id, prefix:)
    source_reservation = acquire_pair_attempt(source_ids, path: source_path, prefix:, role: "source")
    target_reservation = acquire_pair_attempt(target_ids, path: target_path, prefix:, role: "target")
    source = submit_candidate(
      prefix:,
      role: "source",
      ids: source_ids,
      reservation: source_reservation,
      path: source_path,
      head_commit_oid: head_oid(prefix, "source"),
      build_context_path: nil,
      surface: {
        produces: [ { impact_key: source_key, before: "4.2", after: "5.0" } ],
        consumes: [],
        may_affect: [],
        assumes: []
      }
    )
    target = submit_candidate(
      prefix:,
      role: "target",
      ids: target_ids,
      reservation: target_reservation,
      path: target_path,
      head_commit_oid: head_oid(prefix, "target"),
      build_context_path: observed_source ? source_path : nil,
      surface: {
        produces: [],
        consumes: [],
        may_affect: [],
        assumes: [ { impact_key: target_key, predicate: "4.2 remains compatible" } ]
      }
    )
    source = CandidateScenario.complete(source)
    target = CandidateScenario.complete(target)
    registrations = registry_events(change_set_id)
    {
      ids: { change_set_id: },
      source: source.merge(registration: registration_for(registrations, source.fetch(:candidate_id))),
      target: target.merge(registration: registration_for(registrations, target.fetch(:candidate_id)))
    }
  end

  def seed_pair_attempt(prefix:, role:, change_set_id:, path:)
    work_item_id = "W-#{role}-#{prefix}"
    attempt_id = "A-#{role}-#{prefix}"
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Produce #{role} Candidate",
      acceptance_criteria: [ "#{path} is checkpointed" ]
    })
    { change_set_id:, work_item_id:, attempt_id: }
  end

  def activate_pair(change_set_id, prefix:)
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "seed-activate-#{prefix}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    })
    activation = event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
  end

  def acquire_pair_attempt(ids, path:, prefix:, role:)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "seed-acquire-#{role}-#{prefix}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [
        { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "a" * 40 }
      ]
    })
    resource = ResourceScenario.target(
      event_store:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      kind: "file",
      path:,
      base_blob_oid: "c" * 40
    )
    execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "seed-reserve-#{role}-#{prefix}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ resource ],
      lease_duration_seconds: 900
    }).data
  end

  def activate_policy(
    prefix:,
    change_set_id:,
    level: "merge_gate",
    required_evidence: %w[combined_tests contract_compatibility_review]
  )
    message_id = "M-impact-policy-#{prefix}"
    interpretation_id = "I-impact-policy-#{prefix}"
    decision_id = "D-impact-policy-#{prefix}"
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-guidance-impact-policy-#{prefix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-impact-policy-#{prefix}",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [],
        change_set_id:,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation,
      InterpretationInput.impact_policy(
        level:,
        required_evidence:,
        change_set_id:,
        command_id: "cmd-propose-impact-policy-#{prefix}",
        interpretation_id:,
        source_message_id: message_id
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation,
      InterpretationInput.adjudication(
        command_id: "cmd-adjudicate-impact-policy-#{prefix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "cmd-activate-impact-policy-#{prefix}",
        decision_id:,
        interpretation_id:
      )
    )
    decision = decision_events(decision_id).find { _1.type == "DecisionActivated" }
    partition_event = current_partition(change_set_id)
    {
      decision:,
      partition_event:,
      head: Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id:,
        decision_revision: decision.stream_revision,
        event: reference(decision)
      )
    }
  end

  def invocation(pair:, policy:, caused_by: nil)
    source = pair.fetch(:source)
    target = pair.fetch(:target)
    parent = caused_by || source.fetch(:registration)
    loader = Coordinator::Write::CandidateObligations::CandidateEvidenceLoader.new(event_store:)
    source_evidence = loader.call(reference(source.fetch(:registration)))
    target_evidence = loader.call(reference(target.fetch(:registration)))
    identity = Coordinator::Write::CandidateObligations::IdentityBuilder.new.call(
      source: source_evidence,
      target: target_evidence,
      policy_partition_event: reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      rule_version: RULE_VERSION
    )
    command = Coordinator::Write::Commands::CreateCandidateCompatibilityObligation.new(
      command_id: identity.obligation_id,
      actor: { kind: "system", id: "candidate-impact-obligation-policy" },
      obligation_id: identity.obligation_id,
      source_registration: source_evidence.registration_event,
      target_registration: target_evidence.registration_event,
      policy_partition_event: reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      rule_version: RULE_VERSION
    )
    Coordinator::Write::CandidateCompatibilityObligationInvocation.new(
      command:,
      caused_by: parent,
      caused_by_reference: reference(parent)
    )
  end

  def correct_policy(
    policy:,
    prefix:,
    change_set_id:,
    level: "verification_gate",
    required_evidence: [ "combined_tests" ]
  )
    message_id = "M-impact-policy-correction-#{prefix}"
    interpretation_id = "I-impact-policy-correction-#{prefix}"
    decision_id = policy.fetch(:head).decision_id
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-guidance-impact-policy-correction-#{prefix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-impact-policy-correction-#{prefix}",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [],
        change_set_id:,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation,
      InterpretationInput.impact_policy(
        level:,
        required_evidence:,
        change_set_id:,
        command_id: "cmd-propose-impact-policy-correction-#{prefix}",
        interpretation_id:,
        source_message_id: message_id,
        relations: {
          corrects: [ decision_id ],
          supersedes: [],
          exception_to: [],
          revokes: []
        }
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation,
      InterpretationInput.adjudication(
        command_id: "cmd-adjudicate-impact-policy-correction-#{prefix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteCorrectDecision,
      InterpretationInput.correction(
        expected_head: policy.fetch(:head).event.to_h,
        command_id: "cmd-correct-impact-policy-#{prefix}",
        decision_id:,
        interpretation_id:
      )
    )
    decision = decision_events(decision_id).find { _1.type == "DecisionDefinitionCorrected" }
    partition_event = current_partition(change_set_id)
    {
      decision:,
      partition_event:,
      head: Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id:,
        decision_revision: decision.stream_revision,
        event: reference(decision)
      )
    }
  end

  def obligation_events(obligation_id)
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventQueries::VERIFICATION_OBLIGATION_CREATION
    )
  end

  def claim_obligation(created:, prefix:, agent_id: "agent-blue", duration: 300)
    execute(Coordinator::Write::Operations::ExecuteClaimVerificationObligation, {
      command_id: "cmd-claim-#{prefix}",
      actor: { kind: "agent", id: agent_id },
      obligation_id: created.fetch(:result).obligation_id,
      claim_duration_seconds: duration
    }).data
  end

  def submit_compatibility_assessment(
    created:,
    claim:,
    command_id:,
    evidence_kind: "combined_tests",
    conclusion: "passed",
    agent_id: claim.claimant_id,
    run_id: "run-1",
    result_salt: command_id
  )
    execute(
      Coordinator::Write::Operations::ExecuteSubmitCompatibilityAssessment,
      compatibility_assessment_arguments(
        created:,
        claim:,
        command_id:,
        evidence_kind:,
        conclusion:,
        agent_id:,
        run_id:,
        result_salt:
      )
    ).data
  end

  def verification_history(obligation_id)
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Read::Contracts::VerificationObligationSourceEvent::EVENT_TYPES,
        maximum_count: 40,
        direction: :asc
      )
    )
  end

  def waiver_arguments(created:, command_id:, actor_kind: "user", actor_id: "user-label", **reason)
    obligation = created.fetch(:payload)
    {
      command_id:,
      actor: { kind: actor_kind, id: actor_id },
      obligation_id: obligation.obligation_id,
      obligation_validity_input_digest: obligation.validity_input_digest,
      reason: {
        code: reason.fetch(:code, "accepted_risk"),
        summary: reason.fetch(:summary, "User accepts the exact recorded verification risk.")
      }
    }
  end

  def compatibility_assessment_arguments(
    created:,
    claim:,
    command_id:,
    evidence_kind: "combined_tests",
    conclusion: "passed",
    agent_id: claim.claimant_id,
    run_id: "run-1",
    result_salt: command_id
  )
    obligation = created.fetch(:payload)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      obligation_id: obligation.obligation_id,
      claim: { claim_id: claim.claim_id, fencing_token: claim.fencing_token },
      binding: {
        obligation_validity_input_digest: obligation.validity_input_digest,
        source_candidate: {
          candidate_id: obligation.source_candidate.candidate_id,
          head_commit_oid: obligation.source_candidate.head_commit_oid
        },
        target_candidate: {
          candidate_id: obligation.target_candidate.candidate_id,
          head_commit_oid: obligation.target_candidate.head_commit_oid
        }
      },
      assessment: {
        evidence_kind:,
        producer: { name: "coordinator-spec", version: "1.0.0" },
        run_id:,
        test_suite_digest: digest("suite", evidence_kind),
        environment_digest: digest("environment", evidence_kind),
        dependency_graph_digest: digest("dependencies", evidence_kind),
        result_digest: digest("result", result_salt),
        conclusion:,
        findings: compatibility_findings(conclusion),
        produced_at: Coordinator::Shared::SystemClock.new.now
      }
    }
  end

  def compatibility_findings(conclusion)
    return [] if conclusion == "passed"

    [
      {
        code: "assessment-#{conclusion}",
        severity: conclusion == "failed" ? "error" : "warning",
        summary: "Assessment concluded #{conclusion}"
      }
    ]
  end

  def digest(*parts)
    Coordinator::Shared::CanonicalJson.new.sha256(parts)
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
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

  def submit_candidate(prefix:, role:, ids:, reservation:, path:, head_commit_oid:, build_context_path:, surface:)
    candidate_id = "CAN-#{role}-#{prefix}"
    input = CandidateScenario.input(
      prefix: "#{role}-#{prefix}",
      ids:,
      reservation:,
      path:,
      agent_id: "agent-a",
      candidate_id:,
      command_id: "cmd-candidate-#{role}-#{prefix}",
      head_commit_oid:
    )
    if build_context_path
      input = input.merge(build_context: CandidateScenario.build_context_for(build_context_path))
    end
    execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    candidate = {
      candidate_id:,
      input:,
      events: CandidateScenario.candidate_events(candidate_id),
      reservation:
    }
    CandidateScenario.submit_impact(
      candidate,
      command_id: "cmd-impact-#{role}-#{prefix}",
      surface:
    )
    candidate
  end

  def registration_for(registrations, candidate_id)
    registrations.find { _1.data.fetch("candidate_id") == candidate_id }
  end

  def head_oid(prefix, role)
    Coordinator::Shared::CanonicalJson.new
      .sha256([ prefix, role ])
      .delete_prefix("sha256:")
      .first(40)
  end

  def registry_events(change_set_id)
    event_store.read(
      streams.candidate_impact_registry(change_set_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceRegistered" ],
        maximum_count: 8,
        direction: :asc
      )
    )
  end

  def decision_events(decision_id)
    event_store.read(
      streams.decision(decision_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected],
        maximum_count: 8,
        direction: :asc
      )
    )
  end

  def current_partition(change_set_id)
    event_store.read_grouped(
      streams.decision_partition("changeset:#{change_set_id}:candidate"),
      Coordinator::Write::EventQueries::DECISION_PARTITION_LATEST
    ).first
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end
end
