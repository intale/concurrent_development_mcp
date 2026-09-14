# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_coord_context, class: "Coordinator::Read::CoordContext" do
    transient do
      sequence(:work_item_id) { "W-factory-#{_1}" }
      sequence(:attempt_id) { "A-factory-#{_1}" }
      repository_id { SecureRandom.uuid_v7 }
      change_set_status { "active" }
      candidate_checkpoint_count { 0 }
    end

    sequence(:change_set_id) { "CS-factory-#{_1}" }
    projection_version { 2 }
    last_processed_at { Time.utc(2026, 8, 30, 12) }
    source_positions do
      [
        {
          "stream_context" => "DevelopmentPlanning",
          "stream_name" => "ChangeSet",
          "stream_id" => change_set_id,
          "stream_revision" => 2
        },
        {
          "stream_context" => "DevelopmentExecution",
          "stream_name" => "WorkItem",
          "stream_id" => work_item_id,
          "stream_revision" => 2
        }
      ]
    end
    document do
      timestamp = "2026-08-30T12:00:00.000000Z"
      candidate_checkpoints = Array.new(candidate_checkpoint_count) do |index|
        candidate_id = "CAN-#{change_set_id}-#{index}"
        {
          "candidate_id" => candidate_id,
          "candidate_event" => {
            "event_id" => SecureRandom.uuid_v7,
            "type" => "CandidateSubmitted",
            "stream_context" => "DevelopmentIntegration",
            "stream_name" => "Candidate",
            "stream_id" => candidate_id,
            "stream_revision" => 0
          },
          "change_set_id" => change_set_id,
          "work_item_id" => work_item_id,
          "attempt_id" => attempt_id,
          "repository_id" => repository_id,
          "target_branch" => "main",
          "object_format" => "sha1",
          "base_commit_oid" => "a" * 40,
          "head_commit_oid" => "b" * 40,
          "checkpoint_kind" => "intermediate",
          "manifest_digest" => "sha256:#{'c' * 64}",
          "build_context_digest" => nil,
          "attached_at" => timestamp
        }
      end
      {
        "schema" => "coord-context/v1",
        "change_set" => {
          "change_set_id" => change_set_id,
          "goal" => "Coordinate factory work",
          "acceptance_criteria" => [ "The projected context is queryable" ],
          "status" => change_set_status,
          "created_at" => timestamp,
          "activated_at" => change_set_status == "planning" ? nil : timestamp,
          "completed_at" => change_set_status == "completed" ? timestamp : nil
        },
        "work_item_ids" => [ work_item_id ],
        "work_items" => [
          {
            "work_item_id" => work_item_id,
            "change_set_id" => change_set_id,
            "repository_id" => repository_id,
            "goal" => "Implement factory work",
            "acceptance_criteria" => [ "The result is verifiable" ],
            "competitive_mode" => false,
            "status" => "acquired",
            "active_attempt_id" => attempt_id,
            "active_agent_id" => "factory-agent",
            "selected_candidate_id" => nil,
            "selected_candidate_event" => nil,
            "produced_outputs" => [],
            "created_at" => timestamp,
            "made_ready_at" => timestamp,
            "acquired_at" => timestamp,
            "selected_at" => nil,
            "completed_at" => nil
          }
        ],
        "dependencies" => [],
        "attempts" => [
          {
            "attempt_id" => attempt_id,
            "change_set_id" => change_set_id,
            "work_item_id" => work_item_id,
            "agent_id" => "factory-agent",
            "base_snapshots" => [
              {
                "repository_id" => repository_id,
                "object_format" => "sha1",
                "commit_oid" => "a" * 40
              }
            ],
            "status" => "started",
            "authorized_at" => timestamp,
            "started_at" => timestamp,
            "work_intention_set" => nil,
            "selected_candidate_id" => nil,
            "selected_candidate_event" => nil,
            "completed_at" => nil,
            "abandonment_reason" => nil,
            "abandoned_at" => nil
          }
        ],
        "candidate_checkpoints" => candidate_checkpoints
      }
    end
  end

  factory :coordinator_read_coord_context_scope, class: "Coordinator::Read::CoordContextScope" do
    sequence(:change_set_id) { "CS-factory-scope-#{_1}" }
    scope_kind { "change_set" }
    scope_id { change_set_id }
  end
end
