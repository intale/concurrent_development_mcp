# frozen_string_literal: true

RSpec.describe "history migration AgentChoice impact transformer", :event_store do
  POLICY_VERSION = "agent-choice-decision-impact/v1"

  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-impact-change-set" }
  let(:legacy_work_item_id) { "legacy-impact-work-item" }
  let(:legacy_attempt_id) { "legacy-impact-attempt" }
  let(:legacy_decision_id) { "legacy-impact-decision" }
  let(:legacy_choice_id) { "legacy-impact-choice" }
  let(:legacy_assessment_id) { "legacy-impact-assessment" }
  let(:canonical_json) { Coordinator::Write::CanonicalJson.new }

  it "splits the legacy assessment, remaps its evidence, and closes the exact target Choice" do
    history = persist_history
    upper_position = history.fetch(:invalidation).global_position
    preplan_decision_lifecycle(history)
    %i[partition_activated recorded_choice accepted_choice partition_corrected assessment invalidation].each do |name|
      expect(plan(history.fetch(name), upper_position:)).to be_success
    end

    assessment_facts = transform(history.fetch(:assessment), upper_position:).value!
    invalidation_fact = transform(history.fetch(:invalidation), upper_position:).value!.sole
    recorded, accepted_link, decision_link = assessment_facts

    expect(assessment_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1,
      Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1,
      Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1
    ])
    expect(recorded.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(recorded.target_stream.stream_id).not_to eq(legacy_assessment_id)
    expect(recorded.event).to have_attributes(
      assessment_id: recorded.target_stream.stream_id,
      choice_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      attempt_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      assessment: have_attributes(
        outcome: "invalidated",
        reason: "blocking_policy_introduced"
      )
    )
    expect(recorded.event.to_h.keys).to contain_exactly(:assessment_id, :choice_id, :attempt_id, :assessment)
    expect(recorded.event.assessment.to_h.keys).to contain_exactly(
      :before_evaluation, :after_evaluation, :outcome, :reason
    )
    expect(recorded.metadata_extension).to have_attributes(
      policy_version: POLICY_VERSION,
      before_context_digest: match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
      after_context_digest: match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN)
    )
    expect(recorded.metadata_extension.before_context_digest).not_to eq(
      history.fetch(:reconstruction).before_context.digest
    )
    expect(recorded.metadata_extension.before_context_digest).not_to eq(
      recorded.metadata_extension.after_context_digest
    )

    expect(accepted_link.event).to have_attributes(
      role: "accepted_choice",
      source: have_attributes(
        type: "AgentChoiceAccepted",
        stream_id: recorded.event.choice_id,
        stream_revision: 1
      )
    )
    expect(decision_link.event).to have_attributes(
      role: "decision_change",
      source: have_attributes(
        type: "DecisionDefinitionCorrected",
        stream_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
        stream_revision: 3
      )
    )
    expect(recorded.markers).to include(
      "impact-assessment:#{recorded.event.assessment_id}",
      "choice:#{recorded.event.choice_id}",
      "attempt:#{recorded.event.attempt_id}",
      "decision:#{decision_link.event.source.stream_id}",
      "decision-change:#{decision_link.event.source.event_id}"
    )

    expect(invalidation_fact.target_stream).to eq(accepted_link.event.source.then do |source|
      Coordinator::Write::StreamReference.new(
        context: source.stream_context,
        stream_name: source.stream_name,
        stream_id: source.stream_id
      )
    end)
    expect(invalidation_fact.event).to have_attributes(
      choice_id: recorded.event.choice_id,
      reason: "blocking_policy_introduced"
    )
    expect(invalidation_fact.event.to_h.keys).to contain_exactly(:choice_id, :reason)
    expect(invalidation_fact.metadata_extension).to have_attributes(
      previous_context_digest: recorded.metadata_extension.before_context_digest,
      resulting_context_digest: recorded.metadata_extension.after_context_digest
    )

    %i[recorded_choice accepted_choice assessment invalidation].each do |name|
      expect(dispatch(history.fetch(name), upper_position:)).to be_success
    end
    target_assessment = target_store.read(
      recorded.target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AgentChoiceImpactAssessmentRecorded AgentChoiceImpactSourceLinked],
        maximum_count: 3,
        direction: :asc
      )
    )
    target_choice = target_store.read(
      invalidation_fact.target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AgentChoiceRecorded AgentChoiceAccepted AgentChoiceInvalidatedByDecision],
        maximum_count: 3,
        direction: :asc
      )
    )
    expect(target_assessment.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(target_assessment.map(&:type)).to eq(
      %w[AgentChoiceImpactAssessmentRecorded AgentChoiceImpactSourceLinked AgentChoiceImpactSourceLinked]
    )
    expect(target_choice.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(target_choice.last.data.keys).to contain_exactly("choice_id", "reason")
    expect(target_choice.last.metadata).to include(
      "previous_context_digest" => recorded.metadata_extension.before_context_digest,
      "resulting_context_digest" => recorded.metadata_extension.after_context_digest
    )
    snapshot = Coordinator::Write::AgentChoiceImpacts::ChoiceLoader.new(event_store: target_store).call(
      choice_id: recorded.event.choice_id,
      accepted_choice: accepted_link.event.source
    )
    expect(snapshot.invalidation).to eq(invalidation_fact.event)
  end

  it "migrates one terminal legacy impact scan without its timestamps or progress counters" do
    history = persist_history
    scan = persist_completed_scan(history.fetch(:decision_change), caused_by: history.fetch(:corrected))
    upper_position = scan.fetch(:completed).global_position
    preplan_decision_lifecycle(history)
    %i[started progressed completed].each do |name|
      expect(plan(scan.fetch(name), upper_position:)).to be_success
    end

    started_facts = transform(scan.fetch(:started), upper_position:).value!
    progressed_fact = transform(scan.fetch(:progressed), upper_position:).value!.sole
    completed_fact = transform(scan.fetch(:completed), upper_position:).value!.sole
    started, source_link = started_facts

    expect(started_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::AgentChoiceImpactScanStartedV2,
      Coordinator::Write::Events::AgentChoiceImpactScanSourceLinkedV1
    ])
    expect(started.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(started.target_stream.stream_id).not_to eq(scan.fetch(:legacy_scan_id))
    expect(started.event.to_h.keys).to contain_exactly(
      :scan_id, :decision_change, :from_position, :to_position, :page_size
    )
    expect(started.event.decision_change.to_h.keys).not_to include(:changed_at)
    expect(started.event.decision_change).to have_attributes(
      source_event: have_attributes(
        type: "DecisionDefinitionCorrected",
        stream_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
        stream_revision: 3
      ),
      source_command_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      decision_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      affected_partitions: all(have_attributes(anchor_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN)))
    )
    expect(started.event.decision_change.definition_digest).not_to eq(
      history.fetch(:decision_change).definition_digest
    )
    expect(source_link.event).to have_attributes(
      scan_id: started.event.scan_id,
      role: "decision_change",
      source: started.event.decision_change.source_event
    )
    expect(started.markers).to include(
      "impact-scan:#{started.event.scan_id}",
      "decision:#{started.event.decision_change.decision_id}",
      "decision-change:#{started.event.decision_change.source_event.event_id}"
    )

    expect(progressed_fact.target_stream).to eq(started.target_stream)
    expect(progressed_fact.event).to have_attributes(
      scan_id: started.event.scan_id,
      page_number: 1,
      next_from_position: 1,
      decision_change: started.event.decision_change,
      from_position: 0,
      to_position: history.fetch(:corrected).global_position,
      page_size: 50
    )
    expect(progressed_fact.event.to_h.keys).to contain_exactly(
      :scan_id, :page_number, :next_from_position, :decision_change,
      :from_position, :to_position, :page_size
    )
    expect(completed_fact.event.to_h).to eq(scan_id: started.event.scan_id)

    %i[started progressed completed].each do |name|
      expect(dispatch(scan.fetch(name), upper_position:)).to be_success
    end
    target_events = target_store.read(
      started.target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          AgentChoiceImpactScanStarted AgentChoiceImpactScanSourceLinked
          AgentChoiceImpactScanProgressed AgentChoiceImpactScanCompleted
        ],
        maximum_count: 4,
        direction: :asc
      )
    )
    expect(target_events.map(&:stream_revision)).to eq([ 0, 1, 2, 3 ])
    expect(target_events.map(&:type)).to eq(%w[
      AgentChoiceImpactScanStarted AgentChoiceImpactScanSourceLinked
      AgentChoiceImpactScanProgressed AgentChoiceImpactScanCompleted
    ])
    expect(target_events.first.data.keys).not_to include("started_at")
    expect(target_events.fetch(2).data.keys).not_to include(
      "previous_checkpoint", "page_choice_count", "total_choice_count", "progressed_at"
    )
    snapshot = Coordinator::Write::AgentChoiceImpacts::ScanLoader.new(event_store: target_store).call(
      started.event.scan_id
    )
    expect(snapshot.state).to have_attributes(
      status: "completed",
      scan_id: started.event.scan_id,
      decision_change: started.event.decision_change
    )
  end

  it "migrates a policy-skipped scan as one cohesive terminal fact" do
    history = persist_history(retroactivity: "future_only")
    legacy_scan_id = "legacy-skipped-impact-scan"
    skipped = persist_payload(
      stream("AgentGovernance", "AgentChoiceImpactScan", legacy_scan_id),
      Coordinator::Write::Events::AgentChoiceImpactScanSkippedV1.new(
        scan_id: legacy_scan_id,
        decision_change: history.fetch(:decision_change),
        reason: "future_only",
        policy_version: POLICY_VERSION,
        skipped_at: "2026-08-01T10:06:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by: history.fetch(:corrected)
    )
    upper_position = skipped.global_position
    preplan_decision_lifecycle(history)
    expect(plan(skipped, upper_position:)).to be_success

    fact = transform(skipped, upper_position:).value!.sole
    expect(fact.event).to be_a(Coordinator::Write::Events::AgentChoiceImpactScanSkippedV2)
    expect(fact.event.to_h).to eq(scan_id: fact.target_stream.stream_id, reason: "future_only")
    expect(fact.markers).to include("impact-scan:#{fact.target_stream.stream_id}")
    expect(fact.markers.grep(/^decision:/).sole.delete_prefix("decision:")).to match(
      Coordinator::Shared::Types::UUID_V7_PATTERN
    )

    expect(dispatch(skipped, upper_position:)).to be_success
    target_events = target_store.read(
      fact.target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AgentChoiceImpactScanSkipped AgentChoiceImpactScanSourceLinked],
        maximum_count: 2,
        direction: :asc
      )
    )
    expect(target_events.map(&:type)).to eq([ "AgentChoiceImpactScanSkipped" ])
    expect(target_events.sole.data.keys).to contain_exactly("scan_id", "reason")
  end

  it "rejects a nonterminal source scan instead of carrying a source cursor into the target database" do
    history = persist_history
    legacy_scan_id = "legacy-running-impact-scan"
    started = persist_payload(
      stream("AgentGovernance", "AgentChoiceImpactScan", legacy_scan_id),
      Coordinator::Write::Events::AgentChoiceImpactScanStartedV1.new(
        scan_id: legacy_scan_id,
        decision_change: history.fetch(:decision_change),
        from_position: 0,
        to_position: history.fetch(:decision_change).source_global_position,
        page_size: 50,
        policy_version: POLICY_VERSION,
        started_at: "2026-08-01T10:06:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by: history.fetch(:corrected)
    )

    result = transform(started, upper_position: started.global_position)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      message: include("frozen scan history is not terminal")
    )
  end

  def persist_history(retroactivity: "active_attempts")
    persist_scope_roots
    initial_definition = decision_definition("rspec")
    corrected_definition = decision_definition(
      "minitest",
      corrects: [ legacy_decision_id ],
      retroactivity:
    )
    partition = Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(initial_definition).sole
    slot = Coordinator::Write::Decisions::DecisionSlotBuilder.new.call(initial_definition)
    recorded_decision = persist_payload(
      decision_stream,
      decision_recorded(initial_definition)
    )
    activated = persist_payload(
      decision_stream,
      Coordinator::Write::Events::DecisionActivatedV1.new(
        decision_id: legacy_decision_id,
        interpretation_id: "legacy-impact-interpretation-one",
        recorded_event: event_reference(recorded_decision),
        definition_digest: initial_definition.digest,
        slot:,
        partitions: [ partition ],
        rationale: { code: "user_confirmed", summary: "Activate RSpec." },
        activated_at: "2026-08-01T10:01:00.000000Z"
      ),
      caused_by: recorded_decision
    )
    activated_head = decision_head(activated)
    partition_activated = persist_partition(
      partition:,
      head: activated_head,
      active_decisions: [ activated_head ],
      change_kind: "activated",
      command_id: activated.metadata.fetch("command_id"),
      caused_by: activated
    )
    context = decision_context(
      partition:,
      partition_event: partition_activated,
      head: activated_head,
      definition: initial_definition,
      slot:
    )
    recorded_choice = persist_payload(
      choice_stream,
      Coordinator::Write::Events::AgentChoiceRecordedV1.new(
        choice_id: legacy_choice_id,
        choice_type: "testing.framework",
        selected: { option_id: "rspec", summary: "Use RSpec" },
        alternatives: [ { option_id: "minitest", summary: "Use Minitest" } ],
        reason_summary: "The active Decision requires RSpec.",
        context: query_context,
        decision_context: context,
        recorded_at: "2026-08-01T10:02:00.000000Z"
      ),
      caused_by: partition_activated
    )
    accepted_choice = persist_payload(
      choice_stream,
      Coordinator::Write::Events::AgentChoiceAcceptedV1.new(
        choice_id: legacy_choice_id,
        recorded_event: event_reference(recorded_choice),
        context_digest: context.digest,
        assessment: {
          basis: "compliant",
          based_on_decisions: [ activated_head ],
          warnings: []
        },
        accepted_at: "2026-08-01T10:03:00.000000Z"
      ),
      caused_by: recorded_choice
    )
    correction_command_id = SecureRandom.uuid_v7
    corrected = persist_payload(
      decision_stream,
      Coordinator::Write::Events::DecisionDefinitionCorrectedV1.new(
        decision_id: legacy_decision_id,
        interpretation_id: "legacy-impact-interpretation-two",
        source_message_id: "legacy-impact-message-two",
        source_event: dummy_reference("UserUtteranceRecorded", "Conversation", "legacy-impact-conversation"),
        proposal_event: dummy_reference("DecisionInterpretationProposed", "Interpretation", "legacy-impact-message-two"),
        acceptance_event: dummy_reference("DecisionInterpretationAccepted", "Interpretation", "legacy-impact-message-two", 1),
        previous_head: activated_head,
        previous_definition_digest: initial_definition.digest,
        definition: corrected_definition,
        classifier: classifier,
        scope_provenance: scope_provenance("legacy-impact-message-two"),
        previous_slot: slot,
        slot:,
        previous_partitions: [ partition ],
        partitions: [ partition ],
        rationale: { code: "normalization_corrected", summary: "Require Minitest instead." },
        corrected_at: "2026-08-01T10:04:00.000000Z"
      ),
      command_id: correction_command_id,
      caused_by: accepted_choice
    )
    corrected_head = decision_head(corrected)
    partition_corrected = persist_partition(
      partition:,
      head: corrected_head,
      active_decisions: [ corrected_head ],
      change_kind: "corrected",
      command_id: correction_command_id,
      caused_by: corrected
    )
    decision_change = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(
      event_store: source_store
    ).call(corrected).value!
    reconstruction = Coordinator::Write::AgentChoiceImpacts::HistoricalContextReconstructor.new(
      event_store: source_store
    ).call(recorded_choice: load(recorded_choice), decision_change:)
    legacy_change = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1.new(
      decision_change.to_h.merge(changed_at: corrected.created_at.utc.iso8601(6))
    )
    assessment = persist_payload(
      assessment_stream,
      Coordinator::Write::Events::AgentChoiceImpactAssessedV1.new(
        assessment_id: legacy_assessment_id,
        choice_id: legacy_choice_id,
        attempt_id: legacy_attempt_id,
        accepted_choice: event_reference(accepted_choice),
        decision_change: legacy_change,
        assessment: {
          policy_version: POLICY_VERSION,
          before_context_digest: reconstruction.before_context.digest,
          after_context_digest: reconstruction.after_context.digest,
          before_evaluation: reconstruction.before_evaluation,
          after_evaluation: reconstruction.after_evaluation,
          source_advancements: reconstruction.source_advancements,
          outcome: "invalidated",
          reason: "blocking_policy_introduced"
        },
        assessed_at: "2026-08-01T10:05:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by: partition_corrected
    )
    invalidation = persist_payload(
      choice_stream,
      Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV1.new(
        choice_id: legacy_choice_id,
        accepted_choice: event_reference(accepted_choice),
        assessment_event: event_reference(assessment),
        decision_change_event: event_reference(corrected),
        previous_context_digest: reconstruction.before_context.digest,
        resulting_context_digest: reconstruction.after_context.digest,
        reason: "blocking_policy_introduced",
        invalidated_at: "2026-08-01T10:05:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by: assessment
    )

    {
      recorded_decision:, activated:, partition_activated:, recorded_choice:, accepted_choice:,
      corrected:, partition_corrected:, assessment:, invalidation:, reconstruction:,
      decision_change: legacy_change
    }
  end

  def persist_completed_scan(decision_change, caused_by:)
    legacy_scan_id = "legacy-impact-scan"
    target_stream = stream("AgentGovernance", "AgentChoiceImpactScan", legacy_scan_id)
    started = persist_payload(
      target_stream,
      Coordinator::Write::Events::AgentChoiceImpactScanStartedV1.new(
        scan_id: legacy_scan_id,
        decision_change:,
        from_position: 0,
        to_position: decision_change.source_global_position,
        page_size: 50,
        policy_version: POLICY_VERSION,
        started_at: "2026-08-01T10:06:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by:
    )
    progressed = persist_payload(
      target_stream,
      Coordinator::Write::Events::AgentChoiceImpactScanProgressedV1.new(
        scan_id: legacy_scan_id,
        started_event: event_reference(started),
        previous_checkpoint: event_reference(started),
        previous_from_position: 0,
        next_from_position: 1,
        page_number: 1,
        page_choice_count: 1,
        total_choice_count: 1,
        policy_version: POLICY_VERSION,
        progressed_at: "2026-08-01T10:07:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by: started
    )
    completed = persist_payload(
      target_stream,
      Coordinator::Write::Events::AgentChoiceImpactScanCompletedV1.new(
        scan_id: legacy_scan_id,
        started_event: event_reference(started),
        previous_checkpoint: event_reference(progressed),
        previous_from_position: 1,
        final_from_position: decision_change.source_global_position + 1,
        page_count: 2,
        page_choice_count: 0,
        total_choice_count: 1,
        policy_version: POLICY_VERSION,
        completed_at: "2026-08-01T10:08:00.000000Z"
      ),
      policy_version: POLICY_VERSION,
      caused_by: progressed
    )
    { legacy_scan_id:, started:, progressed:, completed: }
  end

  def preplan_decision_lifecycle(history)
    target_stream = decision_target_stream(history.fetch(:recorded_decision))
    [
      [ history.fetch(:recorded_decision), "record-decision", "DecisionRecorded" ],
      [ history.fetch(:recorded_decision), "derive-decision-from-interpretation", "DecisionDerivedFromInterpretation" ],
      [ history.fetch(:activated), "activate-decision", "DecisionActivated" ],
      [ history.fetch(:corrected), "correct-decision-definition", "DecisionDefinitionCorrected" ]
    ].each do |source_event, step_name, event_type|
      preplan_target(source_event, target_stream:, step_name:, event_type:)
    end
  end

  def preplan_target(source_event, target_stream:, step_name:, event_type:)
    process_step = Coordinator::Container["history_migrations.process_step_planner"].call(
      source_event:,
      process_name: "history-migration-#{migration_id}",
      step_name:,
      subject_kind: "source-event",
      subject_id: source_event.id,
      rule_version: "history-migration-transformation/v1",
      allocate_target_entity: true
    )
    result = Coordinator::Container["history_migrations.target_event_planner"].call(
      migration_id:,
      source_event:,
      transformation_step: step_name,
      target_stream:,
      target_event_id: process_step.target_entity_id!,
      target_event_type: event_type,
      caused_by: process_step.event
    )
    expect(result).to be_success
  end

  def decision_target_stream(source_event)
    Coordinator::Container["history_migrations.stream_identity_allocator"].call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      target_stream_context: "HumanGuidance",
      target_stream_name: "Decision",
      identity_role: "decision"
    ).value!.target_stream
  end

  def decision_recorded(definition)
    Coordinator::Write::Events::DecisionRecordedV1.new(
      decision_id: legacy_decision_id,
      interpretation_id: "legacy-impact-interpretation-one",
      source_message_id: "legacy-impact-message-one",
      source_event: dummy_reference("UserUtteranceRecorded", "Conversation", "legacy-impact-conversation"),
      proposal_event: dummy_reference("DecisionInterpretationProposed", "Interpretation", "legacy-impact-message-one"),
      acceptance_event: dummy_reference("DecisionInterpretationAccepted", "Interpretation", "legacy-impact-message-one", 1),
      definition:,
      classifier:,
      scope_provenance: scope_provenance("legacy-impact-message-one"),
      recorded_at: "2026-08-01T10:00:00.000000Z"
    )
  end

  def decision_definition(option_id, corrects: [], retroactivity: "active_attempts")
    input = InterpretationInput.build(
      statement_kind: "directive",
      effect: "require",
      modality: "must",
      value: InterpretationInput.named_choice(option_id),
      scope: InterpretationInput.scope(repository_ids: [ legacy_repository_id ]),
      enforcement: {
        level: "implementation_gate",
        retroactivity:,
        on_violation: "block"
      },
      relations: { corrects:, supersedes: [], exception_to: [], revokes: [] }
    )
    source_message_id = "legacy-impact-definition-#{option_id}"
    proposal = Coordinator::Write::Events::DecisionInterpretationProposedV1.new(
      interpretation_id: "legacy-impact-definition-#{option_id}",
      source_message_id:,
      source_event: dummy_reference("UserUtteranceRecorded", "Conversation", source_message_id),
      source_span: input.fetch(:source_span),
      classifier: input.fetch(:classifier),
      proposed_decision: input.fetch(:proposed_decision),
      scope_provenance: scope_provenance(source_message_id),
      ambiguities: [],
      assessment: {
        status: "accepted_for_activation",
        reasons: [],
        questions: []
      },
      proposed_at: "2026-08-01T09:59:00.000000Z"
    )
    Coordinator::Write::Decisions::DecisionDefinitionBuilder.new.call(
      proposal:,
      valid_from_default: "2026-08-01T10:00:00.000000Z"
    )
  end

  def decision_context(partition:, partition_event:, head:, definition:, slot:)
    observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(query_context).map do |selected|
      if selected == partition
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition: selected,
          partition_revision: partition_event.stream_revision,
          event: event_reference(partition_event),
          active_decisions: [ head ]
        )
      else
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition: selected,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end
    end
    current = Coordinator::Write::Decisions::DecisionCurrentStateV1.new(
      decision_id: legacy_decision_id,
      definition:,
      head:,
      slot:,
      partitions: [ partition ]
    )
    resolved_at = "2026-08-01T10:01:30.000000Z"
    resolution = Coordinator::Write::DecisionContexts::Resolver.new.call(
      context: query_context,
      observations:,
      decisions: [ current ],
      resolved_at:
    )
    Coordinator::Write::DecisionContexts::Builder.new.call(
      context: query_context,
      observations:,
      resolution:,
      resolved_at:
    )
  end

  def query_context
    @query_context ||= Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id: legacy_repository_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      phase: "implementation",
      language: "ruby",
      paths: [ "app/models/order.rb" ],
      environment: nil,
      agent_role: "implementation"
    )
  end

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", legacy_change_set_id), "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", legacy_work_item_id), "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "Attempt", legacy_attempt_id), "AttemptAuthorized")
  end

  def persist_partition(partition:, head:, active_decisions:, change_kind:, command_id:, caused_by:)
    target_stream = stream("HumanGuidance", "DecisionPartition", partition.partition_id)
    latest = source_store.read_latest(
      target_stream,
      Coordinator::Write::LatestEventReadCriteria.new(event_types: [ "DecisionPartitionAdvanced" ])
    )
    revision = latest ? latest.stream_revision + 1 : 0
    persist_payload(
      target_stream,
      Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
        partition:,
        partition_revision: revision,
        decision: head,
        active_decisions:,
        change_kind:,
        advanced_at: "2026-08-01T10:04:30.000000Z"
      ),
      command_id:,
      markers: [ "command:#{command_id}" ],
      caused_by:
    )
  end

  def persist_payload(target_stream, payload, command_id: SecureRandom.uuid_v7, policy_version: "decision-governance/v1", markers: [], caused_by: nil)
    persist_raw(
      target_stream,
      payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      command_id:,
      policy_version:,
      markers:,
      caused_by:
    )
  end

  def persist_raw(target_stream, type, data: {}, schema_version: 1, command_id: SecureRandom.uuid_v7, policy_version: "decision-governance/v1", markers: [], caused_by: nil)
    system_actor = type.start_with?("AgentChoiceImpact") || type == "AgentChoiceInvalidatedByDecision"
    source_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => command_id,
            "actor_kind" => system_actor ? "system" : "agent",
            "actor_id" => system_actor ? "agent-choice-decision-impact" : "impact-migration-agent",
            "recorded_by" => "coordinator",
            "policy_version" => policy_version
          },
          markers:,
          caused_by:,
          correlation_id:
        )
      ]
    ).sole
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def dispatch(source_event, upper_position:)
    dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def decision_head(event)
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: legacy_decision_id,
      decision_revision: event.stream_revision,
      event: event_reference(event)
    )
  end

  def classifier
    Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
      id: "classifier-a",
      version: "decision-classifier-v1",
      ontology_version: 1,
      confidence_millionths: 940_000
    )
  end

  def scope_provenance(message_id)
    Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
      kind: "explicit",
      anchor_level: "repository",
      source_message_id: message_id
    )
  end

  def dummy_reference(type, stream_name, stream_id, revision = 0)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: "HumanGuidance",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def decision_stream
    stream("HumanGuidance", "Decision", legacy_decision_id)
  end

  def choice_stream
    stream("AgentGovernance", "AgentChoice", legacy_choice_id)
  end

  def assessment_stream
    stream("AgentGovernance", "AgentChoiceImpact", legacy_assessment_id)
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end
end
