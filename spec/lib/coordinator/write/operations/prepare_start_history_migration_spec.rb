# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareStartHistoryMigration, :event_store do
  subject(:prepare) { described_class.new }

  let(:input) { { command_id: "bounded-history-rebuild", actor: { kind: "agent", id: "migration-agent" } } }
  let(:store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "freezes an explicitly supplied historical boundary instead of later maintenance traffic" do
    anchor = append_probe
    append_probe

    command = prepare.call(input.merge(source_upper_position: anchor.global_position)).value!

    expect(command.source_upper_position).to eq(anchor.global_position)
    expect(command.migration_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
  end

  it "rejects a requested boundary beyond the authoritative source head" do
    anchor = append_probe

    result = prepare.call(input.merge(source_upper_position: anchor.global_position + 1))

    expect(result).to be_failure
    expect(result.failure.code).to eq(:invalid_input)
  end

  it "continues to capture the current source head when no boundary is supplied" do
    anchor = append_probe

    expect(prepare.call(input).value!.source_upper_position).to eq(anchor.global_position)
  end

  def append_probe
    store.append(
      Coordinator::Write::StreamReference.new(context: "MigrationEvidence", stream_name: "Probe", stream_id: SecureRandom.uuid_v7),
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: "Probe", data: {}) ]
    ).sole
  end
end
