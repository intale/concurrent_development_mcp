# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_merge_authorization, class: "Coordinator::Read::MergeAuthorization" do
    authorization_id { SecureRandom.uuid_v7 }
    sequence(:merge_snapshot_id) { "MS-factory-authorization-#{_1}" }
    outcome { "granted" }
    policy_version { "merge-authorization/v1" }
    snapshot_binding { {} }
    expected_impact_policy { nil }
    evaluation { { "reasons" => [] } }
    input_digest { "sha256:#{'1' * 64}" }
    decision_digest { "sha256:#{'2' * 64}" }
    decided_at_domain { Time.utc(2026, 8, 30, 12, 1) }
    source_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "MergeAuthorizationGranted",
        "stream_context" => "DevelopmentIntegration",
        "stream_name" => "MergeSnapshot",
        "stream_id" => merge_snapshot_id,
        "stream_revision" => 1
      }
    end
    source_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    source_markers { [ "merge-snapshot:#{merge_snapshot_id}" ] }
    source_metadata { { "schema_version" => 1 } }
    sequence(:source_global_position, 1_300)
    source_persisted_at { Time.utc(2026, 8, 30, 12, 1, 1) }
  end
end
