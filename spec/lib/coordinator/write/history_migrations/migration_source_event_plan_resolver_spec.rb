# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::MigrationSourceEventPlanResolver, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:planner) { Coordinator::Write::HistoryMigrations::TargetEventPlanner.new(event_store:) }
  let(:resolver) { described_class.new(event_store:) }
  let(:source_event) do
    event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "LegacyDevelopmentPlanning",
        stream_name: "Decision",
        stream_id: "legacy-decision"
      ),
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "DecisionRecorded") ]
    ).sole
  end

  it "resolves the source plan within the requested migration" do
    first_migration_id = SecureRandom.uuid_v7
    second_migration_id = SecureRandom.uuid_v7
    first_target = target_stream
    second_target = target_stream
    first_event_id = SecureRandom.uuid_v7
    second_event_id = SecureRandom.uuid_v7
    plan(
      migration_id: first_migration_id,
      target_stream: first_target,
      target_event_id: first_event_id
    ).value!
    plan(
      migration_id: second_migration_id,
      target_stream: second_target,
      target_event_id: second_event_id
    ).value!

    result = resolver.call(
      migration_id: second_migration_id,
      source_event:,
      source_event_id: source_event.id
    )

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      event_id: second_event_id,
      stream_id: second_target.stream_id
    )
  end

  it "selects the sole same-type fact when one source event expands into several target facts" do
    migration_id = SecureRandom.uuid_v7
    source = event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "DevelopmentExecution",
        stream_name: "WorkItem",
        stream_id: "legacy-work-item"
      ),
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "WorkItemCompleted") ]
    ).sole
    target = Coordinator::Write::StreamReference.new(
      context: "DevelopmentExecution",
      stream_name: "WorkItem",
      stream_id: SecureRandom.uuid_v7
    )
    output_ids = 2.times.map do |index|
      event_id = SecureRandom.uuid_v7
      plan(
        migration_id:,
        source_event: source,
        transformation_step: format("record-work-item-output-%02d", index + 1),
        target_stream: target,
        target_event_id: event_id,
        target_event_type: "WorkItemOutputRecorded"
      ).value!
      event_id
    end
    completion_id = SecureRandom.uuid_v7
    plan(
      migration_id:,
      source_event: source,
      transformation_step: "complete-work-item",
      target_stream: target,
      target_event_id: completion_id,
      target_event_type: "WorkItemCompleted"
    ).value!

    result = resolver.call(
      migration_id:,
      source_event:,
      source_event_id: source.id
    )

    expect(result).to be_success
    expect(result.value!).to have_attributes(
      event_id: completion_id,
      type: "WorkItemCompleted"
    )
    expect(output_ids).not_to include(result.value!.event_id)
  end

  private

  def target_stream
    Coordinator::Write::StreamReference.new(
      context: "DevelopmentPlanning",
      stream_name: "Decision",
      stream_id: SecureRandom.uuid_v7
    )
  end

  def plan(
    migration_id:,
    target_stream:,
    target_event_id:,
    source_event: self.source_event,
    transformation_step: "record-decision",
    target_event_type: "DecisionRecorded"
  )
    planner.call(
      migration_id:,
      source_event:,
      transformation_step:,
      target_stream:,
      target_event_id:,
      target_event_type:,
      caused_by: source_event
    )
  end
end
