# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_user_utterance, class: "Coordinator::Read::UserUtterance" do
    sequence(:message_id) { "M-factory-#{_1}" }
    conversation_id { "C-#{message_id}" }
    text { "This guidance is available in the read projection." }
    source { "agent_forwarded" }
    anchors do
      {
        "repository_ids" => [],
        "change_set_id" => nil,
        "work_item_id" => nil,
        "attempt_id" => nil
      }
    end
    actor_kind { "agent" }
    actor_id { "factory-agent" }
    policy_status { "evidence_only" }
    event_id { SecureRandom.uuid_v7 }
    event_type { "UserUtteranceRecorded" }
    stream_context { "DevelopmentGuidance" }
    stream_name { "Conversation" }
    stream_id { conversation_id }
    stream_revision { 0 }
    recorded_at_domain { Time.utc(2026, 8, 30, 12) }
  end
end
