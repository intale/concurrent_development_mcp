# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SourceProgress, :event_store do
  let(:reader) { Coordinator::Write::HistoryMigrations::SourceReader.new(client: PgEventstore.client) }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "counts selected domain facts, not excluded positions, across planning and four waves" do
    first, _excluded, second, tail = event_store.append(
      Coordinator::Write::StreamReference.new(context: "CoordinatorMaintenance", stream_name: "ProgressProbe", stream_id: SecureRandom.uuid_v7),
      %w[RepositoryRegistered HistoryMigrationStarted RepositoryDisplayNameChanged ProgressProbe].map do |type|
        PgEventstore::Event.new(type:, data: {})
      end
    )
    snapshot = Coordinator::Write::HistoryMigrations::MigrationSnapshotV1.new(
      migration_id: SecureRandom.uuid_v7, source_config_name: "default", target_config_name: "migration_target",
      source_upper_position: tail.global_position, page_size: 1_000, next_from_position: first.global_position + 1,
      plan_completed: false, application_dependency_wave: 0, application_next_from_position: 0,
      completed: false, abandoned: false, checkpoint_event: tail, latest_revision: 0
    )
    progress = described_class.new(source_reader: reader)

    expect(progress.call(snapshot)).to eq(10.0)
    expect(progress.call(snapshot.new(plan_completed: true, application_dependency_wave: 2,
      application_next_from_position: second.global_position))).to eq(70.0)
    expect(progress.call(snapshot.new(completed: true))).to eq(100.0)
    expect(progress.call(snapshot.new(source_upper_position: nil))).to eq(0.0)
  end

  it "reports only selected suffix facts rather than base history or maintenance gaps" do
    command_id = SecureRandom.uuid_v7
    base, first, _maintenance, second = event_store.append(
      Coordinator::Write::StreamReference.new(context: "CoordinatorMaintenance", stream_name: "SuffixProgressProbe", stream_id: SecureRandom.uuid_v7),
      [
        PgEventstore::Event.new(type: "RepositoryRegistered", data: {}),
        PgEventstore::Event.new(type: "DevelopmentArtifactCreated", data: {}, markers: [ "command:#{command_id}" ]),
        PgEventstore::Event.new(type: "HistoryMigrationStarted", data: {}),
        PgEventstore::Event.new(type: "DevelopmentArtifactContentChanged", data: {}, markers: [ "command:#{command_id}" ])
      ]
    )
    snapshot = Coordinator::Write::HistoryMigrations::MigrationSnapshotV1.new(
      migration_id: SecureRandom.uuid_v7, source_config_name: "default", target_config_name: "migration_target",
      source_after_position: base.global_position, source_command_ids: [ command_id ],
      source_upper_position: second.global_position, page_size: 1000, next_from_position: first.global_position + 1,
      plan_completed: false, application_dependency_wave: 0, application_next_from_position: base.global_position + 1,
      completed: false, abandoned: false, checkpoint_event: second, latest_revision: 0
    )
    progress = described_class.new(source_reader: reader)

    expect(progress.call(snapshot)).to eq(10.0)
    expect(progress.call(snapshot.new(plan_completed: true, application_dependency_wave: 2,
      application_next_from_position: second.global_position))).to eq(70.0)
    expect(progress.call(snapshot.new(completed: true))).to eq(100.0)
  end
end
