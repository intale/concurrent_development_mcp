# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_agent_choice, class: "Coordinator::Read::AgentChoice" do
    sequence(:choice_id) { "CHO-factory-#{_1}" }
    choice_type { "testing.framework" }
    observation_status { "recorded" }
    selected { { "option_id" => "rspec", "summary" => "RSpec" } }
    alternatives { [ { "option_id" => "minitest", "summary" => "Minitest" } ] }
    reason_summary { "Use the testing framework represented by this available read fixture." }
    context do
      {
        "workspace_id" => nil,
        "repository_id" => SecureRandom.uuid_v7,
        "change_set_id" => "CS-#{choice_id}",
        "work_item_id" => "W-#{choice_id}",
        "attempt_id" => "A-#{choice_id}",
        "phase" => "implementation",
        "language" => "ruby",
        "paths" => [ "spec/models/order_spec.rb" ],
        "environment" => "test",
        "agent_role" => "implementer"
      }
    end
    context_digest { "sha256:#{'a' * 64}" }
    decision_context do
      partitions = %w[repo changeset workitem attempt].map do |anchor_kind|
        {
          "partition" => {
            "partition_id" => "testing.framework:#{anchor_kind}:#{choice_id}",
            "topic_root" => "testing",
            "anchor_kind" => anchor_kind,
            "anchor_id" => choice_id
          },
          "partition_revision" => nil,
          "event" => nil,
          "active_decisions" => []
        }
      end
      {
        "document" => {
          "schema" => "decision-context/v1",
          "resolution_policy" => "testing-framework-resolution/v1",
          "topic_id" => "testing.framework",
          "query_context" => context,
          "partitions" => partitions,
          "effective_decision" => nil,
          "shadowed_decisions" => [],
          "conflict" => nil
        },
        "digest" => context_digest,
        "resolved_at" => "2026-08-30T12:00:00.000000Z"
      }
    end
    assessment { nil }
    recorded_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "AgentChoiceRecorded",
        "stream_context" => "DevelopmentGovernance",
        "stream_name" => "AgentChoice",
        "stream_id" => choice_id,
        "stream_revision" => 0
      }
    end
    recorded_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    recorded_markers { [ "choice:#{choice_id}" ] }
    recorded_metadata { { "schema_version" => 1 } }
    recorded_at_domain { Time.utc(2026, 8, 30, 12) }
    recorded_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }

    trait :accepted do
      observation_status { "accepted" }
      assessment { { "basis" => "no_policy", "based_on_decisions" => [], "warnings" => [] } }
      accepted_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "AgentChoiceAccepted",
          "stream_context" => "DevelopmentGovernance",
          "stream_name" => "AgentChoice",
          "stream_id" => choice_id,
          "stream_revision" => 1
        }
      end
      accepted_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
      accepted_markers { [ "choice:#{choice_id}" ] }
      accepted_metadata { { "schema_version" => 1 } }
      accepted_at_domain { Time.utc(2026, 8, 30, 12, 1) }
      accepted_at_store { Time.utc(2026, 8, 30, 12, 1, 1) }
    end
  end
end
