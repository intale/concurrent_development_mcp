# frozen_string_literal: true

RSpec.describe "history migration AgentChoice transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:canonical_json) { Coordinator::Write::CanonicalJson.new }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-choice-change-set" }
  let(:legacy_work_item_id) { "legacy-choice-work-item" }
  let(:legacy_attempt_id) { "legacy-choice-attempt" }
  let(:legacy_decision_id) { "legacy-choice-decision" }
  let(:legacy_choice_id) { "legacy-agent-choice" }

  it "remaps a V1 choice and its nested authoritative references into narrow UUIDv7 V2 facts" do
    history = persist_history
    upper_position = history.fetch(:accepted).global_position
    preplan_decision(history.fetch(:decision), upper_position:)

    %i[partition recorded accepted].each do |name|
      expect(plan(history.fetch(name), upper_position:)).to be_success
    end

    recorded = transform(history.fetch(:recorded), upper_position:).value!.sole
    accepted = transform(history.fetch(:accepted), upper_position:).value!.sole

    expect(recorded.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(recorded.target_stream.stream_id).not_to eq(legacy_choice_id)
    expect(recorded.event).to be_a(Coordinator::Write::Events::AgentChoiceRecordedV2)
    expect(recorded.event.choice_id).to eq(recorded.target_stream.stream_id)
    expect(recorded.event.to_h.keys).to contain_exactly(
      :choice_id, :choice_type, :selected, :alternatives, :context, :decision_context, :reason_summary
    )
    expect(recorded.event.context).to have_attributes(
      repository_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      change_set_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      work_item_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      attempt_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(recorded.event.decision_context.document.query_context).to eq(recorded.event.context)
    expect(recorded.event.decision_context.to_h.keys).to contain_exactly(:document)
    context_digest = canonical_json.sha256(recorded.event.decision_context.document.to_h)
    expect(context_digest).not_to eq(history.fetch(:context).digest)

    repository_observation = recorded.event.decision_context.document.partitions.find do |observation|
      observation.partition.anchor_kind == "repo"
    end
    expect(repository_observation.partition.anchor_id).to eq(recorded.event.context.repository_id)
    expect(repository_observation.partition.partition_id).to eq(
      "repo:#{recorded.event.context.repository_id}:testing"
    )
    expect(repository_observation.event).to have_attributes(
      type: "DecisionAddedToPartition",
      stream_revision: 0
    )
    expect(repository_observation.active_decisions.sole).to have_attributes(
      decision_id: match(Coordinator::Shared::Types::UUID_V7_PATTERN),
      decision_revision: 0,
      event: have_attributes(type: "DecisionActivated", stream_revision: 0)
    )

    expect(accepted.event).to be_a(Coordinator::Write::Events::AgentChoiceAcceptedV2)
    expect(accepted.event.to_h.keys).to contain_exactly(:choice_id, :assessment)
    expect(accepted.event.choice_id).to eq(recorded.event.choice_id)
    expect(accepted.event.assessment.based_on_decisions).to eq(repository_observation.active_decisions)
    expect(accepted.metadata_extension.context_digest).to eq(context_digest)
    expect(accepted.markers).to include(
      "choice:#{recorded.event.choice_id}",
      "repository:#{recorded.event.context.repository_id}",
      "decision:#{repository_observation.active_decisions.sole.decision_id}",
      "decision-partition:#{repository_observation.partition.partition_id}"
    )

    %i[partition recorded accepted].each do |name|
      expect(dispatch(history.fetch(name), upper_position:)).to be_success
    end

    target_events = target_store.read(
      recorded.target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AgentChoiceRecorded AgentChoiceAccepted],
        maximum_count: 2,
        direction: :asc
      )
    )
    expect(target_events.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(target_events.map(&:type)).to eq(%w[AgentChoiceRecorded AgentChoiceAccepted])
    expect(target_events.flat_map { _1.data.keys }).not_to include(
      "recorded_at", "recorded_event", "context_digest", "accepted_at"
    )
    expect(target_events.first.data.fetch("decision_context").keys).to contain_exactly("document")
    expect(target_events.last.metadata).to include(
      "context_digest" => context_digest,
      "actor_kind" => "agent",
      "actor_id" => "choice-migration-agent"
    )
  end

  def persist_history
    persist_scope_roots
    decision = persist_raw(
      stream("HumanGuidance", "Decision", legacy_decision_id),
      "DecisionActivated"
    )
    head = decision_head(decision)
    partitions = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(query_context)
    repository_partition = partitions.find { _1.anchor_kind == "repo" }
    partition = persist_payload(
      stream("HumanGuidance", "DecisionPartition", repository_partition.partition_id),
      Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
        partition: repository_partition,
        partition_revision: 0,
        decision: head,
        active_decisions: [ head ],
        change_kind: "activated",
        advanced_at: "2026-08-01T10:00:00.000000Z"
      ),
      caused_by: decision
    )
    observations = partitions.map do |value|
      if value == repository_partition
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition: value,
          partition_revision: partition.stream_revision,
          event: event_reference(partition),
          active_decisions: [ head ]
        )
      else
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition: value,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end
    end
    context = decision_context(observations)
    choice_stream = stream("AgentGovernance", "AgentChoice", legacy_choice_id)
    recorded = persist_payload(
      choice_stream,
      Coordinator::Write::Events::AgentChoiceRecordedV1.new(
        choice_id: legacy_choice_id,
        choice_type: "testing.framework",
        selected: { option_id: "rspec", summary: "Use RSpec" },
        alternatives: [ { option_id: "minitest", summary: "Use Minitest" } ],
        reason_summary: "The active testing Decision selects RSpec.",
        context: query_context,
        decision_context: context,
        recorded_at: "2026-08-01T10:01:00.000000Z"
      ),
      caused_by: partition
    )
    accepted = persist_payload(
      choice_stream,
      Coordinator::Write::Events::AgentChoiceAcceptedV1.new(
        choice_id: legacy_choice_id,
        recorded_event: event_reference(recorded),
        context_digest: context.digest,
        assessment: {
          basis: "compliant",
          based_on_decisions: [ head ],
          warnings: []
        },
        accepted_at: "2026-08-01T10:02:00.000000Z"
      ),
      caused_by: recorded
    )

    { decision:, partition:, recorded:, accepted:, context: }
  end

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", legacy_change_set_id), "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", legacy_work_item_id), "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "Attempt", legacy_attempt_id), "AttemptAuthorized")
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

  def decision_context(observations)
    document = Coordinator::Write::DecisionContexts::ContextDocumentV1.new(
      schema: "decision-context/v1",
      resolution_policy: "testing-framework-resolution/v1",
      topic_id: "testing.framework",
      query_context:,
      partitions: observations,
      effective_decision: nil,
      shadowed_decisions: [],
      conflict: nil
    )
    Coordinator::Write::DecisionContexts::ContextV1.new(
      document:,
      digest: canonical_json.sha256(document.to_h),
      resolved_at: "2026-08-01T10:00:30.000000Z"
    )
  end

  def preplan_decision(source_event, upper_position:)
    allocation = Coordinator::Container["history_migrations.stream_identity_allocator"].call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      target_stream_context: "HumanGuidance",
      target_stream_name: "Decision",
      identity_role: "decision"
    ).value!
    process_step = Coordinator::Container["history_migrations.process_step_planner"].call(
      source_event:,
      process_name: "history-migration-#{migration_id}",
      step_name: "activate-decision",
      subject_kind: "source-event",
      subject_id: source_event.id,
      rule_version: "history-migration-transformation/v1",
      allocate_target_entity: true
    )
    result = Coordinator::Container["history_migrations.target_event_planner"].call(
      migration_id:,
      source_event:,
      transformation_step: "activate-decision",
      target_stream: allocation.target_stream,
      target_event_id: process_step.target_entity_id!,
      target_event_type: "DecisionActivated",
      caused_by: process_step.event
    )
    expect(result).to be_success
    expect(
      Coordinator::Container["history_migrations.source_trace_planner"].call(
        migration_id:,
        source_event:,
        target_plans: [ result.value! ]
      )
    ).to be_success
    expect(source_event.global_position).to be <= upper_position
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
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def persist_payload(target_stream, payload, caused_by: nil)
    persist_raw(
      target_stream,
      payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      caused_by:
    )
  end

  def persist_raw(target_stream, type, data: {}, schema_version: 1, caused_by: nil)
    source_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => SecureRandom.uuid_v7,
            "actor_kind" => "agent",
            "actor_id" => "choice-migration-agent",
            "recorded_by" => "coordinator",
            "policy_version" => "testing-framework-resolution/v1"
          },
          caused_by:,
          correlation_id:
        )
      ]
    ).sole
  end

  def decision_head(event)
    Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: legacy_decision_id,
      decision_revision: event.stream_revision,
      event: event_reference(event)
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

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
  end
end
