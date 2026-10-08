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

  it "rejects partial suffix definitions, inverted ranges, malformed IDs, and duplicate selectors" do
    uuid = SecureRandom.uuid_v7
    invalid = [
      { source_after_position: 1 },
      { source_after_position: 4, source_upper_position: 3, source_command_ids: [ uuid ] },
      { source_after_position: 1, source_upper_position: 3, source_command_ids: [ "request-label" ] },
      { source_after_position: 1, source_upper_position: 3, source_command_ids: [ uuid, uuid ] }
    ]
    invalid.each do |attributes|
      expect(prepare.call(input.merge(attributes)).failure.code).to eq(:invalid_input)
    end
  end

  def append_probe
    repository_id = SecureRandom.uuid_v7
    payload = Coordinator::Write::Events::RepositoryRegisteredV2.new(
      repository_id:, scope: "project:migration-start", repository_key: "probe"
    )
    store.append(
      Coordinator::Write::StreamFactory.new.repository(repository_id),
      [ PgEventstore::Event.new(type: "RepositoryRegistered", data: payload.to_h, metadata: { "schema_version" => 2 }) ]
    ).sole
  end
end
