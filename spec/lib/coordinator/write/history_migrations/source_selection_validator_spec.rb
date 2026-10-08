# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SourceSelectionValidator, :event_store do
  let(:reader) { Coordinator::Write::HistoryMigrations::SourceReader.new(client: PgEventstore.client) }
  let(:store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:command_id) { SecureRandom.uuid_v7 }
  let(:artifact_id) { SecureRandom.uuid_v7 }
  let(:anchor) { store.append(streams.repository(SecureRandom.uuid_v7), [ PgEventstore::Event.new(type: "RepositoryRegistered", data: {}) ]).sole }

  it "accepts only complete current-contract new streams inside the selected immutable range" do
    first, last = command_facts
    artifact = artifact_fact
    result = validate(artifact.global_position)
    expect(result).to be_success
    expect(first.global_position).to be > anchor.global_position
    expect(last.type).to eq("CommandSucceeded")
  end

  it "rejects omitted roots and unsupported command tools" do
    first, = command_facts(tool: "history_migration_start")
    artifact = artifact_fact
    expect(validate(artifact.global_position)).to be_failure
    expect(validate(artifact.global_position, after_position: first.global_position)).to be_failure
  end

  it "rejects a dangling concrete source reference before admission" do
    command_facts
    artifact_fact
    observation_id = SecureRandom.uuid_v7
    reference = {
      event_id: SecureRandom.uuid_v7, type: "DevelopmentArtifactCreated",
      stream_context: "DevelopmentMemory", stream_name: "DevelopmentArtifact",
      stream_id: artifact_id, stream_revision: 0
    }
    last = store.append(streams.development_artifact_observation(observation_id), [
      PgEventstore::Event.new(type: "DevelopmentArtifactObservationRecorded", data: { observation_id: }, metadata: { schema_version: 1 }, markers: [ "command:#{command_id}" ]),
      PgEventstore::Event.new(type: "DevelopmentArtifactObservationFactLinked", data: { observation_id:, artifact_id:, role: "creation", observed_fact: reference }, metadata: { schema_version: 1 }, markers: [ "command:#{command_id}" ])
    ]).last
    expect(validate(last.global_position).failure.message).to include("reference")
  end

  it "rejects a causal parent outside the selected range" do
    command_facts
    artifact = artifact_fact(caused_by: anchor)
    expect(validate(artifact.global_position).failure.message).to include("causal parent")
  end

  it "does not silently accept unsupported trailing facts in a selected stream" do
    command_facts
    artifact_fact
    last = store.append(streams.development_artifact(artifact_id), [ PgEventstore::Event.new(type: "UnmodeledFact", data: {}, markers: [ "command:#{command_id}" ]) ]).sole
    expect(validate(last.global_position).failure.message).to include("complete new source streams")
  end

  it "rejects an oversized selection using a bounded sentinel page" do
    command_facts
    artifact_fact
    last = store.append(streams.development_artifact(artifact_id), Array.new(1000) {
      PgEventstore::Event.new(type: "DevelopmentArtifactLabelAdded", data: { artifact_id:, label: "probe" }, metadata: { schema_version: 1 }, markers: [ "command:#{command_id}" ])
    }).last
    expect(validate(last.global_position).failure.message).to include("exceeds 1000")
  end

  def command_facts(tool: "development_artifact_capture")
    anchor
    store.append(streams.command(command_id), [
      PgEventstore::Event.new(type: "CommandRegistered", data: { command_id:, request_id: "suffix-probe", tool_name: tool }, metadata: { schema_version: 1 }, markers: [ "command:#{command_id}" ]),
      PgEventstore::Event.new(type: "CommandSucceeded", data: { command_id: }, metadata: { schema_version: 1 }, markers: [ "command:#{command_id}" ])
    ])
  end

  def artifact_fact(caused_by: nil)
    data = { artifact_id: }
    store.append(streams.development_artifact(artifact_id), [ PgEventstore::Event.new(
      type: "DevelopmentArtifactCreated", data:, metadata: { schema_version: 1 },
      markers: [ "command:#{command_id}" ], caused_by:
    ) ]).sole
  end

  def validate(upper_position, after_position: anchor.global_position)
    described_class.new(source_reader: reader).call(after_position:, upper_position:, command_ids: [ command_id ])
  end
end
