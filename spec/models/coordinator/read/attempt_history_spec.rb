# frozen_string_literal: true

RSpec.describe Coordinator::Read::AttemptHistory, :read_model do
  it "persists a complete read-side Attempt fixture through its factory" do
    attempt = create(:coordinator_read_attempt_history)

    expect(attempt).to be_persisted
    expect(attempt.id).to eq(attempt.attempt_id)
    expect(attempt.base_snapshots.sole).to include(
      "object_format" => "sha1",
      "commit_oid" => "a" * 40
    )
    expect(attempt.authorization_event).to include(
      "type" => "AttemptAuthorized",
      "stream_id" => attempt.attempt_id
    )
  end
end
