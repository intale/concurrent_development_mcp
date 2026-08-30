# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_attempt_history, class: "Coordinator::Read::AttemptHistory" do
    sequence(:attempt_id) { "attempt-#{_1}" }
    sequence(:change_set_id) { "change-set-#{_1}" }
    sequence(:work_item_id) { "work-item-#{_1}" }
    sequence(:authorized_global_position, 1)

    agent_id { "factory-agent" }
    base_snapshots do
      [
        {
          "repository_id" => SecureRandom.uuid_v7,
          "object_format" => "sha1",
          "commit_oid" => "a" * 40
        }
      ]
    end
    status { "authorized" }
    authorization_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "AttemptAuthorized",
        "stream_context" => "DevelopmentCoordination",
        "stream_name" => "Attempt",
        "stream_id" => attempt_id,
        "stream_revision" => 0
      }
    end
    authorized_at_domain { Time.utc(2026, 8, 30, 12) }
  end
end
