# frozen_string_literal: true

module CandidateImpactObligationAcceptanceWorld
  REQUIRED_EVIDENCE = %w[combined_tests contract_compatibility_review].freeze
  REGISTRY_RULE_VERSION = "candidate-impact-registry-sweep/v1"
  PAIR_RULE_VERSION = "candidate-impact-pair-scan/v1"
  OBLIGATION_RULE_VERSION = "candidate-compatibility-obligation/v1"

  def prepare_candidate_obligation_coordination(prefix:)
    @obligation_prefix = prefix
    @obligation_candidates = prepare_impact_change_set(
      prefix: "OBL-#{prefix}",
      rows: [
        {
          "role" => "source",
          "candidate_id" => "CAN-CUC-OBL-#{prefix}-RAILS",
          "repository" => "billing",
          "head" => "b",
          "path" => "Gemfile.lock",
          "observes_path" => "no"
        },
        {
          "role" => "target",
          "candidate_id" => "CAN-CUC-OBL-#{prefix}-APP",
          "repository" => "billing",
          "head" => "e",
          "path" => "app/services/checkout.rb",
          "observes_path" => "no"
        }
      ]
    )
    @obligation_change_set_id = @obligation_candidates.dig(
      "source", :arguments, :change_set_id
    )
  end

  def submit_candidate_obligation_surface(role)
    candidate = @obligation_candidates.fetch(role)
    arguments = impact_arguments(
      candidate,
      command_id: "cmd-cuc-obligation-impact-#{@obligation_prefix.downcase}-#{role}",
      actor_id: "rails-impact-analyzer-#{role}",
      surface: candidate_obligation_surface(role)
    )
    task_id = submit_impact_task(arguments)
    assert_successful_task(task_id, "Candidate obligation #{role} surface")
    project_impact(candidate)
    candidate[:impact_arguments] = arguments
    candidate[:impact_task_id] = task_id
    candidate[:registration] = candidate_obligation_registrations.find do |event|
      event.data.fetch("candidate_id") == candidate.dig(:arguments, :candidate_id)
    end
    assert_acceptance(candidate[:registration], "Candidate obligation #{role} registration is missing")
    candidate[:registration]
  end

  def submit_candidate_obligation_pair
    submit_candidate_obligation_surface("source")
    submit_candidate_obligation_surface("target")
    derive_candidate_obligation_id if @obligation_policy
  end

  def activate_candidate_obligation_policy(level:)
    suffix = @obligation_prefix.downcase
    message_id = "M-CUC-OBL-#{@obligation_prefix}"
    interpretation_id = "I-CUC-OBL-#{@obligation_prefix}"
    decision_id = "D-CUC-OBL-#{@obligation_prefix}"
    task_ids = []
    task_ids << submit_and_execute(
      "guidance_record",
      command_id: "cmd-cuc-obligation-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-CUC-OBL-#{@obligation_prefix}",
      source: "mcp_client",
      text: "Apply #{level} to Rails Candidate impact.",
      anchors: {
        repository_ids: [],
        change_set_id: @obligation_change_set_id,
        work_item_id: nil,
        attempt_id: nil
      }
    )
    task_ids << submit_and_execute(
      "decision_interpretation_propose",
      **candidate_obligation_policy_proposal(
        suffix:,
        message_id:,
        interpretation_id:,
        level:
      )
    )
    task_ids << submit_and_execute(
      "decision_interpretation_adjudicate",
      command_id: "cmd-cuc-obligation-adjudicate-#{suffix}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: message_id,
      interpretation_id:,
      action: "accept",
      rationale: {
        code: "user_confirmed",
        summary: "The Candidate impact policy matches the user's coordination rule."
      },
      clarification: nil
    )
    task_ids << submit_and_execute(
      "decision_activate",
      command_id: "cmd-cuc-obligation-activate-#{suffix}",
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id:,
      rationale: {
        code: "user_confirmed",
        summary: "Activate the accepted Candidate impact policy."
      }
    )
    task_ids.each { assert_successful_task(_1, "Candidate impact policy") }

    decision_event = decision_events(decision_id).find { _1.type == "DecisionActivated" }
    partition_event = candidate_policy_partition_events.last
    assert_acceptance(decision_event, "Candidate impact policy activation is missing")
    assert_acceptance(partition_event, "Candidate impact policy partition advancement is missing")
    @obligation_policy = {
      level:,
      decision_id:,
      decision_event:,
      partition_event:,
      head: Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id:,
        decision_revision: decision_event.stream_revision,
        event: candidate_obligation_event_reference(decision_event)
      )
    }
    derive_candidate_obligation_id if candidate_obligation_registrations.length == 2
    @obligation_policy
  end

  def project_candidate_obligation_policy
    decision_id = @obligation_policy.fetch(:decision_id)
    events = decision_events(decision_id)
    recorded = events.find { _1.type == "DecisionRecorded" }
    activated = events.find { _1.type == "DecisionActivated" }
    assert_acceptance(recorded && activated, "Candidate impact Decision history is incomplete")
    slot_id = activated.data.fetch("slot").fetch("slot_id")
    projector = Coordinator::Container["projectors.decision_governance_v1"]
    [
      recorded,
      activated,
      *decision_slot_events(slot_id),
      *candidate_policy_partition_events
    ].each { projector.call(_1) }
  end

  def drive_candidate_policy_source(redeliver: true)
    process_manager = candidate_obligation_process_manager
    source = @obligation_policy.fetch(:partition_event)
    process_manager.call(source)
    process_manager.call(source) if redeliver
    started = candidate_registry_sweep_events.find do
      _1.type == "CandidateImpactRegistrySweepStarted"
    end
    return unless started

    process_manager.call(started)
    process_manager.call(started) if redeliver
    drive_candidate_pair_scans(
      registrations: candidate_obligation_registrations,
      redeliver:
    )
    derive_candidate_obligation_id if candidate_obligation_registrations.length == 2
  end

  def drive_candidate_registration_source(role, redeliver: true)
    registration = @obligation_candidates.dig(role, :registration)
    assert_acceptance(registration, "Candidate obligation #{role} registration is missing")
    process_manager = candidate_obligation_process_manager
    process_manager.call(registration)
    process_manager.call(registration) if redeliver
    drive_candidate_pair_scans(registrations: [ registration ], redeliver:)
    derive_candidate_obligation_id if candidate_obligation_registrations.length == 2
  end

  def candidate_obligation_events
    return [] unless @obligation_id

    event_store.read(
      streams.verification_obligation(@obligation_id),
      Coordinator::Write::EventQueries::VERIFICATION_OBLIGATION_CREATION
    )
  end

  def candidate_obligation_payload
    event = candidate_obligation_events.sole
    Coordinator::Container["event_schema_registry"].load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def project_candidate_obligation(redeliver: true)
    event = candidate_obligation_events.sole
    projector = Coordinator::Container["projectors.verification_obligations_v1"]
    projector.call(event)
    projector.call(event) if redeliver
  end

  def candidate_obligation_page(**filters)
    call_tool(
      "verification_obligations_list",
      { change_set_id: @obligation_change_set_id, **filters }
    ).dig("result", "structuredContent")
  end

  def candidate_obligation_impact_view
    candidate_impact_view(
      @obligation_candidates.dig("source", :arguments, :candidate_id)
    )
  end

  def candidate_obligation_pair_scan_events
    candidate_obligation_registrations.flat_map do |registration|
      %w[outgoing incoming].flat_map do |direction|
        candidate_pair_scan_events(registration, direction)
      end
    end
  end

  private

  def candidate_obligation_surface(role)
    empty = { produces: [], consumes: [], may_affect: [], assumes: [] }
    if role == "source"
      empty.merge(
        produces: [
          {
            impact_key: "dependency:rubygems:rails",
            before: "4.2.11",
            after: "5.0.0"
          }
        ]
      )
    else
      empty.merge(
        assumes: [
          {
            impact_key: "dependency:rubygems:rails",
            predicate: "4.2.11 remains compatible"
          }
        ]
      )
    end
  end

  def candidate_obligation_policy_proposal(suffix:, message_id:, interpretation_id:, level:)
    {
      command_id: "cmd-cuc-obligation-propose-#{suffix}",
      actor: { kind: "agent", id: "candidate-impact-classifier" },
      interpretation_id:,
      source_message_id: message_id,
      source_span: nil,
      classifier: {
        id: "candidate-impact-classifier",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 950_000
      },
      proposed_decision: {
        statement_kind: "directive",
        topic_id: "candidate.impact_policy",
        effect: "require",
        modality: "must",
        value: {
          schema: "string-set/v1",
          name: nil,
          items: REQUIRED_EVIDENCE,
          target_kind: nil,
          target_id: nil,
          action: nil
        },
        scope: candidate_obligation_policy_scope,
        conditions: {
          phases: [],
          languages: [],
          tags: [],
          repository_kinds: [],
          artifact_kinds: [],
          environments: []
        },
        validity: { valid_from: nil, valid_until: nil, until_event: nil },
        authority: { actor_id: "user-label", role: "project-owner" },
        enforcement: {
          level:,
          retroactivity: "all_unmerged_candidates",
          on_violation: %w[verification_gate merge_gate].include?(level) ? "block" : "warn"
        },
        relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
      },
      ambiguities: []
    }
  end

  def candidate_obligation_policy_scope
    {
      workspace_id: nil,
      repository_ids: [],
      branch_selectors: [],
      change_set_id: @obligation_change_set_id,
      work_item_id: nil,
      attempt_id: nil,
      candidate_id: nil,
      path_selectors: [],
      symbol_selectors: [],
      contract_selectors: [],
      schema_selectors: [],
      environments: [],
      agent_roles: []
    }
  end

  def candidate_obligation_registrations
    event_store.read(
      streams.candidate_impact_registry(@obligation_change_set_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceRegistered" ],
        maximum_count: 8,
        direction: :asc
      )
    )
  end

  def candidate_policy_partition_events
    event_store.read(
      streams.decision_partition("changeset:#{@obligation_change_set_id}:candidate"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 8,
        direction: :asc
      )
    )
  end

  def derive_candidate_obligation_id
    registrations = candidate_obligation_registrations
    source_reference = candidate_obligation_event_reference(
      registrations.find do |event|
        event.data.fetch("candidate_id") == @obligation_candidates.dig(
          "source", :arguments, :candidate_id
        )
      end
    )
    target_reference = candidate_obligation_event_reference(
      registrations.find do |event|
        event.data.fetch("candidate_id") == @obligation_candidates.dig(
          "target", :arguments, :candidate_id
        )
      end
    )
    loader = Coordinator::Write::CandidateObligations::CandidateEvidenceLoader.new(
      event_store:
    )
    identity = Coordinator::Write::CandidateObligations::IdentityBuilder.new.call(
      source: loader.call(source_reference),
      target: loader.call(target_reference),
      policy_head: @obligation_policy.fetch(:head),
      rule_version: OBLIGATION_RULE_VERSION
    )
    @obligation_id = identity.obligation_id
  end

  def candidate_registry_sweep_events
    identity = Coordinator::Write::CandidateObligationScans::IdentityBuilder.new
    scan_id = identity.registry_sweep(
      policy_partition_event: candidate_obligation_event_reference(
        @obligation_policy.fetch(:partition_event)
      ),
      policy_head: @obligation_policy.fetch(:head),
      rule_version: REGISTRY_RULE_VERSION
    )
    event_store.read_grouped(
      streams.candidate_impact_registry_sweep(scan_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_REGISTRY_SWEEP_STATE
    )
  end

  def drive_candidate_pair_scans(registrations:, redeliver:)
    process_manager = candidate_obligation_process_manager
    registrations.each do |registration|
      %w[outgoing incoming].each do |direction|
        started = candidate_pair_scan_events(registration, direction).find do
          _1.type == "CandidateImpactPairScanStarted"
        end
        next unless started

        process_manager.call(started)
        process_manager.call(started) if redeliver
      end
    end
  end

  def candidate_pair_scan_events(registration, direction)
    identity = Coordinator::Write::CandidateObligationScans::IdentityBuilder.new
    scan_id = identity.pair_scan(
      source_registration: candidate_obligation_event_reference(registration),
      direction:,
      policy_partition_event: candidate_obligation_event_reference(
        @obligation_policy.fetch(:partition_event)
      ),
      policy_head: @obligation_policy.fetch(:head),
      rule_version: PAIR_RULE_VERSION
    )
    event_store.read_grouped(
      streams.candidate_impact_pair_scan(scan_id),
      Coordinator::Write::EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_STATE
    )
  end

  def candidate_obligation_event_reference(event)
    assert_acceptance(event, "Referenced Candidate obligation event is missing")
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def candidate_obligation_process_manager
    Coordinator::Container["process_managers.candidate_impact_obligation_policy"]
  end
end

World(CandidateImpactObligationAcceptanceWorld)
