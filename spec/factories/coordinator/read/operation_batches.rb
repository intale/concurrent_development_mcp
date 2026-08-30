# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_operation_batch, class: "Coordinator::Read::OperationBatch" do
    batch_id { SecureRandom.uuid_v7 }
    target_tool { "skill_publish" }
    total { 2 }
    page_size { 1_000 }
    manifest_digest { "sha256:#{'a' * 64}" }
    encoded_byte_size { 1_024 }
    status { "completed_with_errors" }
    succeeded_count { 1 }
    rejected_count { 1 }
    cancellation_requested { false }
    terminal_kind { "completed" }
    created_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "OperationBatchCreated",
        "stream_context" => "CoordinatorControl",
        "stream_name" => "OperationBatch",
        "stream_id" => batch_id,
        "stream_revision" => 0
      }
    end
    created_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    created_markers { [ "operation-batch:#{batch_id}" ] }
    created_metadata { { "schema_version" => 1 } }
    sequence(:created_global_position, 1_500)
    created_at_domain { Time.utc(2026, 8, 30, 12) }
    created_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }
    terminal_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "OperationBatchCompleted",
        "stream_context" => "CoordinatorControl",
        "stream_name" => "OperationBatch",
        "stream_id" => batch_id,
        "stream_revision" => 3
      }
    end
    terminal_actor { { "kind" => "system", "id" => "operation-batch-runner", "authenticated" => false } }
    terminal_markers { created_markers }
    terminal_metadata { { "schema_version" => 1 } }
    terminal_global_position { created_global_position + 3 }
    terminal_at_domain { Time.utc(2026, 8, 30, 12, 3) }
    terminal_at_store { Time.utc(2026, 8, 30, 12, 3, 1) }
  end

  factory :coordinator_read_operation_batch_item, class: "Coordinator::Read::OperationBatchItem" do
    association :operation_batch, factory: :coordinator_read_operation_batch
    batch_id { operation_batch.batch_id }
    sequence(:item_index, 0)
    target_tool { "skill_publish" }
    sequence(:command_id) { "item-factory-#{_1}" }
    canonical_input_digest { "sha256:#{'b' * 64}" }
    arguments do
      {
        "command_id" => command_id,
        "actor" => { "kind" => "agent", "id" => "factory-agent" },
        "name" => "review",
        "scope" => "project:alpha",
        "expected_revision" => 0,
        "description" => "Review a change",
        "instructions" => "Inspect the complete diff.",
        "assets" => []
      }
    end
  end

  factory :coordinator_read_operation_batch_outcome,
          class: "Coordinator::Read::OperationBatchOutcome" do
    association :operation_batch, factory: :coordinator_read_operation_batch
    batch_id { operation_batch.batch_id }
    sequence(:item_index, 0)
    sequence(:command_id) { "item-outcome-factory-#{_1}" }
    canonical_input_digest { "sha256:#{'b' * 64}" }
    status { "succeeded" }
    result do
      {
        "status" => "ok",
        "summary" => "Skill revision published.",
        "command_id" => command_id,
        "receipt" => "command:#{command_id}",
        "context_token" => nil,
        "data" => {
          "skill_id" => "skill:v1:#{'c' * 64}",
          "name" => "review",
          "scope" => "project:alpha",
          "revision" => 1,
          "content_digest" => "sha256:#{'d' * 64}",
          "asset_count" => 0,
          "publication_event" => {
            "event_id" => SecureRandom.uuid_v7,
            "type" => "SkillRevisionPublished",
            "stream_context" => "AgentKnowledge",
            "stream_name" => "Skill",
            "stream_id" => "skill:v1:#{'c' * 64}",
            "stream_revision" => 0
          },
          "published_at" => "2026-08-30T12:01:00.000000Z"
        },
        "warnings" => [],
        "next_actions" => []
      }
    end
    outcome_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => status == "succeeded" ? "OperationBatchItemSucceeded" : "OperationBatchItemRejected",
        "stream_context" => "CoordinatorControl",
        "stream_name" => "OperationBatch",
        "stream_id" => batch_id,
        "stream_revision" => item_index + 1
      }
    end
    outcome_actor { { "kind" => "system", "id" => "operation-batch-runner", "authenticated" => false } }
    outcome_markers { [ "operation-batch:#{batch_id}" ] }
    outcome_metadata { { "schema_version" => 1 } }
    sequence(:outcome_global_position, 1_600)
    finished_at_domain { Time.utc(2026, 8, 30, 12, 1) }
    finished_at_store { Time.utc(2026, 8, 30, 12, 1, 1) }

    trait :rejected do
      status { "rejected" }
      result do
        {
          "status" => "conflict",
          "summary" => "Skill revision changed.",
          "command_id" => command_id,
          "receipt" => nil,
          "context_token" => nil,
          "data" => {
            "code" => "skill_revision_conflict",
            "message" => "Skill revision changed",
            "details" => {
              "skill_id" => "skill:v1:#{'c' * 64}",
              "name" => "review",
              "scope" => "project:alpha",
              "expected_revision" => 0,
              "current_revision" => 1
            }
          },
          "warnings" => [],
          "next_actions" => []
        }
      end
    end
  end
end
