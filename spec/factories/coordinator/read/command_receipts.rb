# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_command_receipt, class: "Coordinator::Read::CommandReceipt" do
    sequence(:command_id) { "cmd-factory-#{_1}" }
    command_stream_revision { 1 }
    tool_name { "change_set_create" }
    canonical_input_digest { "sha256:#{'f' * 64}" }
    status { "ok" }
    summary { "ChangeSet created." }
    receipt { command_id }
    completion do
      {
        "command_id" => command_id,
        "tool_name" => tool_name,
        "canonical_input_digest" => canonical_input_digest,
        "status" => status,
        "summary" => summary,
        "receipt" => receipt,
        "data" => { "change_set_id" => "CS-#{command_id}" },
        "warnings" => [],
        "next_actions" => [],
        "emitted_events" => [
          {
            "event_id" => SecureRandom.uuid_v7,
            "type" => "ChangeSetCreated",
            "stream_context" => "DevelopmentPlanning",
            "stream_name" => "ChangeSet",
            "stream_id" => "CS-#{command_id}",
            "stream_revision" => 0
          }
        ],
        "completed_at" => "2026-08-30T12:00:00.000000Z"
      }
    end
    completed_at_domain { Time.utc(2026, 8, 30, 12) }
  end
end
