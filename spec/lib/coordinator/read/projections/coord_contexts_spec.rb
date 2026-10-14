# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projections::CoordContexts do
  it "bounds recent Attempt/checkpoint detail while leaving absolute totals independent" do
    state = described_class.initial
    state[:attempts] = Array.new(100) do |index|
      { attempt_id: "A-#{index.to_s.rjust(3, '0')}", status: "abandoned", authorized_at: (Time.utc(2026, 9, 17, 10) + index).iso8601(6) }
    end
    state[:candidate_checkpoints] = state.fetch(:attempts).map { { attempt_id: _1.fetch(:attempt_id), candidate_id: "CAN-#{_1.fetch(:attempt_id)}" } }
    fold, patches = build_fold(state)
    event = started_event
    fold.apply(event, source: definition)

    projected = patches.update_groups.flat_map(&:rows).sole.fetch(:document)
    expect(projected.fetch(:attempts).length).to eq(100)
    expect(projected.fetch(:candidate_checkpoints).length).to eq(99)
    expect(projected.fetch(:attempts).map { _1.fetch(:attempt_id) }).to include("A-current")
    expect(projected.fetch(:candidate_checkpoints).map { _1.fetch(:attempt_id) }).not_to include("A-000")
  end

  it "retains an older active Attempt ahead of newer terminal detail" do
    state = described_class.initial
    state[:attempts] = Array.new(100) do |index|
      { attempt_id: "A-#{index}", status: "completed", authorized_at: (Time.utc(2026, 9, 17, 10) + index).iso8601(6) }
    end
    fold, patches = build_fold(state)
    fold.apply(started_event, source: definition.merge(authorized_at: "2026-09-17T09:00:00.000000Z"))

    attempts = patches.update_groups.flat_map(&:rows).sole.fetch(:document).fetch(:attempts)
    expect(attempts.length).to eq(100)
    expect(attempts.map { _1.fetch(:attempt_id) }).to include("A-current")
    expect(attempts.count { _1.fetch(:status) == "completed" }).to eq(99)
  end

  def build_fold(state)
    contexts = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :change_set_id ])
    histories = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: [ :attempt_id ])
    scopes = Coordinator::Read::Projections::Batches::ColumnPatches.new(identity_columns: %i[scope_kind scope_id])
    [ described_class.new(contexts:, histories:, scopes:, documents: { "CS-bounded" => state }), contexts ]
  end

  def started_event
    ProjectionEventFactory.build(payload: Coordinator::Write::Events::AttemptStartedV2.new(attempt_id: "A-current"),
      stream: Coordinator::Write::StreamFactory.new.attempt("A-current"), stream_revision: 4, global_position: 1000,
      policy_version: "work-item-acquisition/v1", created_at: Time.utc(2026, 9, 17, 12))
  end

  def definition
    { attempt_id: "A-current", change_set_id: "CS-bounded", work_item_id: "W-bounded", agent_id: "agent-current",
      base_snapshots: [ { repository_id: SecureRandom.uuid_v7, object_format: "sha1", commit_oid: "a" * 40 } ],
      authorization_event: Coordinator::Read::Projections::Source.reference(started_event), authorized_global_position: 999,
      authorized_at: "2026-09-17T12:00:00.000000Z", started_at: "2026-09-17T12:00:01.000000Z" }
  end
end
