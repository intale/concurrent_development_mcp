# frozen_string_literal: true

RSpec.describe "history migration planning entity target dispatch", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "legacy-dispatch-change-set" }
  let(:source_stream) do
    Coordinator::Write::StreamReference.new(
      context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      stream_id: change_set_id
    )
  end

  it "uses target database occurrence time and preserves a completion rule as metadata" do
    correlation_id = SecureRandom.uuid_v7
    created = persist_source(
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id:,
        goal: "Prove target occurrence semantics",
        created_at: "2001-06-01T00:00:00.000000Z"
      ),
      correlation_id:
    )
    completed = persist_source(
      Coordinator::Write::Events::ChangeSetCompletedV1.new(
        change_set_id:,
        work_item_completions: [ completion_evidence ],
        release_set_completion_event: nil,
        rule_version: "change-set-completion/v1",
        completed_at: "2001-06-02T00:00:00.000000Z"
      ),
      correlation_id:
    )
    upper_position = completed.global_position

    [ created, completed ].each do |source_event|
      expect(plan(source_event, upper_position:)).to be_success
    end
    writes = [ created, completed ].map do |source_event|
      dispatch(source_event, upper_position:).value!
    end

    target_events = writes.flat_map(&:events)
    target_stream = Coordinator::Write::StreamReference.new(
      context: target_events.first.stream.context,
      stream_name: target_events.first.stream.stream_name,
      stream_id: target_events.first.stream.stream_id
    )
    persisted = target_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ChangeSetCreated ChangeSetGoalDefined ChangeSetCompleted],
        maximum_count: 3,
        direction: :asc
      )
    )

    expect(persisted.map(&:type)).to eq(%w[ChangeSetCreated ChangeSetGoalDefined ChangeSetCompleted])
    expect(persisted.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(persisted.flat_map { _1.data.keys }).not_to include("created_at", "completed_at")
    expect(persisted.map(&:created_at)).to all(be > created.created_at)
    expect(persisted.last.metadata.fetch("policy_version")).to eq("change-set-completion/v1")
    expect(persisted.last.metadata.fetch("migration_source")).to include(
      "event_id" => completed.id,
      "created_at" => completed.created_at.utc.iso8601(6)
    )
    expect(persisted.map(&:correlation_id).uniq.one?).to be(true)
  end

  def plan(source_event, upper_position:)
    planner.call(
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

  def persist_source(payload, correlation_id:)
    source_store.append(
      source_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => "legacy-change-set-command",
            "actor_kind" => "agent",
            "actor_id" => "legacy-agent",
            "recorded_by" => "coordinator"
          },
          markers: [ "change-set:#{change_set_id}" ],
          correlation_id:
        )
      ]
    ).sole
  end

  def completion_evidence
    reference = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type: "WorkItemCompleted",
      stream_context: "DevelopmentExecution",
      stream_name: "WorkItem",
      stream_id: "legacy-work-item",
      stream_revision: 4
    )
    Coordinator::Write::ChangeSetCompletions::WorkItemEvidenceV1.new(
      change_set_id:,
      work_item_id: "legacy-work-item",
      repository_id: SecureRandom.uuid_v7,
      attempt_id: "legacy-attempt",
      candidate_id: "legacy-candidate",
      candidate_event: reference,
      selected_event: reference,
      completed_event: reference,
      completed_at: "2001-06-02T00:00:00.000000Z"
    )
  end
end
