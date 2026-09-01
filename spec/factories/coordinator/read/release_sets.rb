# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_release_set, class: "Coordinator::Read::ReleaseSet" do
    sequence(:release_set_id) { "RS-factory-#{_1}" }
    change_set_id { "CS-#{release_set_id}" }
    transient do
      repository_ids do
        [
          "018f0f4d-4e45-7abc-8def-000000000081",
          "018f0f4d-4e45-7abc-8def-000000000082"
        ]
      end
    end
    ordered_members do
      repository_ids.each_with_index.map do |repository_id, index|
        {
          "position" => index + 1,
          "repository_id" => repository_id,
          "target_branch" => "main",
          "object_format" => "sha1",
          "merge_snapshot_id" => "MS-#{release_set_id}-#{index + 1}",
          "change_set_id" => change_set_id,
          "target_base_commit_oid" => "a" * 40,
          "merge_commit_oid" => (index + 1).to_s * 40,
          "snapshot_binding" => {},
          "authorization_event" => {},
          "authorization_decision_digest" => "sha256:#{'a' * 64}",
          "ordered_candidates" => [
            {
              "candidate_id" => "CAN-#{release_set_id}-#{index + 1}",
              "change_set_id" => change_set_id,
              "work_item_id" => "W-#{release_set_id}-#{index + 1}",
              "attempt_id" => "A-#{release_set_id}-#{index + 1}",
              "repository_id" => repository_id,
              "target_branch" => "main",
              "object_format" => "sha1",
              "base_commit_oid" => "a" * 40,
              "head_commit_oid" => "b" * 40,
              "manifest_digest" => "sha256:#{'b' * 64}",
              "candidate_event" => {},
              "manifest_event" => {}
            }
          ]
        }
      end
    end
    release_digest { "sha256:#{'c' * 64}" }
    status { "prepared" }
    verification_status { "unverified" }
    integrations { [] }
    verifications { [] }
    activation { nil }
    compensation_request { nil }
    completion { nil }
    preparation_policy_version { "release-set-preparation/v1" }
    prepared_at_domain { Time.utc(2026, 8, 30, 12) }
    prepared_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "ReleaseSetPrepared",
        "stream_context" => "DevelopmentIntegration",
        "stream_name" => "ReleaseSet",
        "stream_id" => release_set_id,
        "stream_revision" => 0
      }
    end
    prepared_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    prepared_markers { [ "release-set:#{release_set_id}" ] }
    prepared_metadata { { "schema_version" => 1 } }
    sequence(:prepared_global_position, 1_400)
    prepared_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }
  end
end
