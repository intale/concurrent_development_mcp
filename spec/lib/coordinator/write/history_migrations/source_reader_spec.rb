# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SourceReader, :event_store do
  subject(:reader) { described_class.new(client: PgEventstore.client) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:stream) do
    Coordinator::Write::StreamReference.new(
      context: "CoordinatorMaintenance",
      stream_name: "MigrationSourceProbe",
      stream_id: SecureRandom.uuid_v7
    )
  end

  it "reads the source head and pages only through explicit public bounds" do
    first, second = event_store.append(
      stream,
      [
        PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "RepositoryRegistered", data: { "number" => 1 }),
        PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "RepositoryRegistered", data: { "number" => 2 })
      ]
    )

    page = reader.page(
      Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
        from_position: first.global_position,
        to_position: second.global_position,
        page_size: 1
      )
    )

    expect(reader.head_position).to eq(second.global_position)
    expect(reader.head_position(to_position: first.global_position)).to eq(first.global_position)
    expect(page.map(&:id)).to eq([ first.id ])
    expect(
      reader.page(
        Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
          from_position: second.global_position,
          to_position: first.global_position,
          page_size: 1
        )
      )
    ).to be_empty
  end

  it "excludes maintenance and unknown event types in the database query, before paging or freezing the head" do
    first, maintenance, second, excluded_tail = event_store.append(stream, [
      PgEventstore::Event.new(type: "RepositoryRegistered", data: {}),
      PgEventstore::Event.new(type: "HistoryMigrationStarted", data: {}),
      PgEventstore::Event.new(type: "RepositoryDisplayNameChanged", data: {}),
      PgEventstore::Event.new(type: "MigrationSourceProbe", data: {})
    ])

    page = reader.page(Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
      from_position: first.global_position, to_position: excluded_tail.global_position, page_size: 2
    ))
    expect(page.map(&:id)).to eq([ first.id, second.id ])
    expect(reader.head_position).to eq(second.global_position)
    expect(reader.page(Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
      from_position: maintenance.global_position, to_position: excluded_tail.global_position, page_size: 1
    )).map(&:id)).to eq([ second.id ])
  end

  it "keeps the fixed allowlist aligned with all explicitly supported source contracts" do
    expected = Coordinator::Write::HistoryMigrations::SourceEventSchemaRegistry::DEFINITIONS.keys.map(&:first).uniq
    expect(described_class::EVENT_TYPES).to match_array(expected)
    expect(described_class::EVENT_TYPES.grep(/\AHistoryMigration/)).to be_empty
  end

  it "applies the same positive command selection before paging and head lookup" do
    command_id = SecureRandom.uuid_v7
    first, maintenance, second, unrelated = event_store.append(stream, [
      PgEventstore::Event.new(type: "DevelopmentArtifactCreated", data: {}, markers: [ "command:#{command_id}" ]),
      PgEventstore::Event.new(type: "ProcessStepPlanned", data: {}, markers: [ "command:#{command_id}" ]),
      PgEventstore::Event.new(type: "DevelopmentArtifactContentChanged", data: {}, markers: [ "command:#{command_id}" ]),
      PgEventstore::Event.new(type: "DevelopmentArtifactCreated", data: {}, markers: [ "command:#{SecureRandom.uuid_v7}" ])
    ])
    criteria = Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
      from_position: first.global_position, to_position: unrelated.global_position,
      page_size: 2, source_command_ids: [ command_id ]
    )
    expect(reader.page(criteria).map(&:id)).to eq([ first.id, second.id ])
    expect(reader.head_position(to_position: unrelated.global_position, source_command_ids: [ command_id ])).to eq(second.global_position)
    expect(reader.head_position(to_position: unrelated.global_position, source_after_position: second.global_position, source_command_ids: [ command_id ])).to be_nil
    expect(reader.page(criteria.new(from_position: maintenance.global_position, page_size: 1)).map(&:id)).to eq([ second.id ])
  end

  it "includes Task lifecycle commands through the immutable submitted Task identity" do
    command_id = SecureRandom.uuid_v7
    task_id = SecureRandom.uuid_v7
    submitted, completed = event_store.append(stream, [
      PgEventstore::Event.new(type: "CoordinationTaskSubmitted", data: { task_id: }, markers: [ "command:#{command_id}" ]),
      PgEventstore::Event.new(type: "CoordinationTaskCompleted", data: { task_id: }, markers: [ "command:#{SecureRandom.uuid_v7}", "task:#{task_id}" ])
    ])
    events = reader.page(Coordinator::Write::HistoryMigrations::SourcePageCriteriaV1.new(
      from_position: submitted.global_position, to_position: completed.global_position,
      page_size: 10, source_command_ids: [ command_id ]
    ))
    expect(events.map(&:id)).to eq([ submitted.id, completed.id ])
  end
end
