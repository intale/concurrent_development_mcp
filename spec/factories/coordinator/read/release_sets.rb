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
          "candidate_id" => "CAN-#{release_set_id}-#{index + 1}"
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
        "stream_revision" => repository_ids.length + 1
      }
    end
    prepared_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    prepared_markers { [ "release-set:#{release_set_id}" ] }
    prepared_metadata do
      {
        "schema_version" => 2,
        "release_digest" => release_digest,
        "policy_version" => preparation_policy_version
      }
    end
    sequence(:prepared_global_position, 1_400)
    prepared_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }
  end
end
