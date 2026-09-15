# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteStartHistoryMigration, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:migration_id) { "01999999-9999-7999-8999-999999999999" }
  let(:command) do
    Coordinator::Write::Commands::StartHistoryMigration.new(
      command_id: "migration-start-1",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "migration-agent"),
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position: 41,
      page_size: 1_000
    )
  end

  it "persists the six facts atomically, without occurrence timestamps in event data" do
    result = operation.call_command(command)
    events = history

    expect(result).to be_success
    expect(events.map(&:type)).to eq(described_class::EVENT_TYPES)
    expect(events.map(&:stream_revision)).to eq((0..5).to_a)
    expect(events.map(&:id)).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(events.map(&:correlation_id).uniq).to contain_exactly(
      a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(events.flat_map { _1.data.keys }).not_to include(
      "created_at", "started_at", "selected_at", "frozen_at"
    )
    expect(result.value!.data.to_h).to include(
      migration_id:,
      source_config_name: "default",
      target_config_name: "migration_target",
      source_upper_position: 41,
      page_size: 1_000,
      outcome: "started"
    )
    expect(result.value!.emitted_events.length).to eq(6)
  end

  it "resolves an exact replay without another fact and rejects a changed definition" do
    expect(operation.call_command(command)).to be_success

    replay = operation.call_command(command)
    conflict = operation.call_command(command.class.new(command.attributes.merge(page_size: 500)))

    expect(replay.value!.data.outcome).to eq("existing")
    expect(replay.value!.emitted_events).to be_empty
    expect(conflict.failure.code).to eq(:history_migration_conflict)
    expect(history.length).to eq(6)
  end

  def history
    event_store.read(
      streams.history_migration(migration_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: described_class::EVENT_TYPES,
        maximum_count: 6,
        direction: :asc
      )
    )
  end
end
