# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_merge_snapshot, class: "Coordinator::Read::MergeSnapshot" do
    sequence(:merge_snapshot_id) { "MS-factory-#{_1}" }
    repository_id { SecureRandom.uuid_v7 }
    target_branch { "main" }
    object_format { "sha1" }
    target_base_commit_oid { "a" * 40 }
    ordered_candidates do
      candidate_id = "CAN-#{merge_snapshot_id}"
      [
        {
          "candidate_id" => candidate_id,
          "change_set_id" => "CS-#{merge_snapshot_id}",
          "work_item_id" => "WI-#{merge_snapshot_id}",
          "attempt_id" => "ATT-#{merge_snapshot_id}",
          "repository_id" => repository_id,
          "target_branch" => target_branch,
          "object_format" => object_format,
          "base_commit_oid" => target_base_commit_oid,
          "head_commit_oid" => "b" * 40,
          "manifest_digest" => "sha256:#{'c' * 64}",
          "candidate_event" => {
            "event_id" => SecureRandom.uuid_v7,
            "type" => "CandidateSubmitted",
            "stream_context" => "DevelopmentIntegration",
            "stream_name" => "Candidate",
            "stream_id" => candidate_id,
            "stream_revision" => 0
          },
          "manifest_event" => {
            "event_id" => SecureRandom.uuid_v7,
            "type" => "CandidateManifestDeclared",
            "stream_context" => "DevelopmentIntegration",
            "stream_name" => "Candidate",
            "stream_id" => candidate_id,
            "stream_revision" => 1
          }
        }
      ]
    end
    merge_commit_oid { "9" * 40 }
    producer { "git-merge" }
    sequence(:run_id) { "run-factory-#{_1}" }
    produced_at_domain { Time.utc(2026, 8, 30, 12) }
    snapshot_digest { "sha256:#{'d' * 64}" }
    policy_version { "merge-snapshot-registration/v1" }
    evidence_status { "attributed_unverified" }
    registered_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "MergeSnapshotRegistered",
        "stream_context" => "DevelopmentIntegration",
        "stream_name" => "MergeSnapshot",
        "stream_id" => merge_snapshot_id,
        "stream_revision" => 0
      }
    end
    registered_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    registered_markers { [ "merge-snapshot:#{merge_snapshot_id}" ] }
    registered_metadata { { "schema_version" => 2, "policy_version" => policy_version } }
    registered_causation_id { nil }
    registered_correlation_id { SecureRandom.uuid_v7 }
    sequence(:registered_global_position, 1_200)
    registered_at_domain { Time.utc(2026, 8, 30, 12, 0, 1) }
    registered_at_store { Time.utc(2026, 8, 30, 12, 0, 2) }
    verification_status { "unverified" }
    verification_policy_version { "merge-snapshot-verification/v1" }
    verification_submissions { [] }
    verified_decision { nil }
    observation { nil }
  end
end
