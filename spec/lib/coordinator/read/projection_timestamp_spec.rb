# frozen_string_literal: true

RSpec.describe Coordinator::Read::ProjectionTimestamp do
  subject(:projection_timestamp) { described_class.new }

  it "uses persisted event time and never regresses after delayed delivery" do
    older = event_at(Time.utc(2026, 9, 1, 12))
    newer = event_at(Time.utc(2026, 9, 1, 12, 1))

    first = projection_timestamp.call(current: nil, event: newer)
    delayed = projection_timestamp.call(current: first, event: older)

    expect(first).to eq(newer.created_at)
    expect(delayed).to eq(newer.created_at)
  end

  def event_at(created_at)
    repository_id = SecureRandom.uuid_v7
    ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::RepositoryRegisteredV2.new(
        repository_id:,
        scope: "project:event-time",
        repository_key: repository_id
      ),
      stream: Coordinator::Write::StreamFactory.new.repository(repository_id),
      stream_revision: 0,
      global_position: 1,
      policy_version: "repository-registration/v1",
      created_at:
    )
  end
end
