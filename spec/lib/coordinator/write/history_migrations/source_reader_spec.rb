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
        PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "MigrationSourceProbe", data: { "number" => 1 }),
        PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "MigrationSourceProbe", data: { "number" => 2 })
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
end
