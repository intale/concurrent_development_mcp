# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_candidate, class: "Coordinator::Read::Candidate" do
    sequence(:candidate_id) { "CAN-factory-#{_1}" }
    sequence(:submitted_global_position, 100)
    change_set_id { "CS-#{candidate_id}" }
    work_item_id { "W-#{candidate_id}" }
    attempt_id { "A-#{candidate_id}" }
    agent_id { "factory-agent" }
    repository_id { SecureRandom.uuid_v7 }
    target_branch { "main" }
    object_format { "sha1" }
    base_commit_oid { "a" * 40 }
    head_commit_oid { "b" * 40 }
    checkpoint_kind { "final" }
    intention_set_id { SecureRandom.uuid_v7 }
    intention_policy_version { "coordinator-work-intention/v1" }
    intentions do
      [
        {
          "intention_id" => SecureRandom.uuid_v7,
          "resource_id" => SecureRandom.uuid_v7,
          "resource_kind" => "file",
          "resource_path" => "lib/factory.rb",
          "base_blob_oid" => "c" * 40,
          "mode" => "shared",
          "purpose" => "Implement the assigned Candidate checkpoint",
          "context" => nil,
          "fencing_token" => 1
        }
      ]
    end
    manifest_digest { "sha256:#{'d' * 64}" }
    build_context_digest { nil }
    evidence_status { "attributed_unverified" }
    submitted_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "CandidateSubmitted",
        "stream_context" => "DevelopmentIntegration",
        "stream_name" => "Candidate",
        "stream_id" => candidate_id,
        "stream_revision" => 0
      }
    end
    submitted_actor { { "kind" => "agent", "id" => agent_id, "authenticated" => false } }
    submitted_markers { [ "candidate:#{candidate_id}" ] }
    submitted_metadata { { "schema_version" => 3 } }
    submitted_at_domain { Time.utc(2026, 8, 30, 12) }
    submitted_at_store { submitted_at_domain }

    trait :manifest_observed do
      manifest do
        {
          "policy_version" => "candidate-change-manifest/v1",
          "digest" => manifest_digest,
          "files" => [
            {
              "status" => "modified",
              "old_path" => "lib/factory.rb",
              "new_path" => "lib/factory.rb",
              "old_blob_oid" => "c" * 40,
              "new_blob_oid" => "d" * 40,
              "old_mode" => "100644",
              "new_mode" => "100644"
            }
          ],
          "collector" => {
            "kind" => "agent",
            "id" => agent_id,
            "collector_version" => "factory-v1"
          }
        }
      end
      manifest_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "CandidateChangeManifestCaptured",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "Candidate",
          "stream_id" => candidate_id,
          "stream_revision" => 1
        }
      end
      manifest_actor { submitted_actor }
      manifest_markers { submitted_markers }
      manifest_metadata { { "schema_version" => 1 } }
      manifest_global_position { submitted_global_position + 1 }
      manifest_at_domain { submitted_at_domain + 1.second }
      manifest_at_store { submitted_at_store + 1.second }
    end

    trait :build_context_observed do
      build_context_digest { "sha256:#{'e' * 64}" }
      build_context do
        {
          "policy_version" => "candidate-build-context/v1",
          "digest" => build_context_digest,
          "inputs" => [
            { "kind" => "runtime_version", "path" => ".ruby-version", "blob_oid" => "e" * 40 }
          ],
          "environment" => [ { "name" => "RAILS_ENV", "value" => "test" } ],
          "dependency_graph_digest" => nil,
          "test_environment_digest" => nil,
          "collector" => {
            "kind" => "agent",
            "id" => agent_id,
            "collector_version" => "factory-v1"
          }
        }
      end
      build_context_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "CandidateBuildContextCaptured",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "Candidate",
          "stream_id" => candidate_id,
          "stream_revision" => 2
        }
      end
      build_context_actor { submitted_actor }
      build_context_markers { submitted_markers }
      build_context_metadata { { "schema_version" => 1 } }
      build_context_global_position { submitted_global_position + 2 }
      build_context_at_domain { submitted_at_domain + 2.seconds }
      build_context_at_store { submitted_at_store + 2.seconds }
    end

    trait :impact_surface_observed do
      impact_surface do
        {
          "policy_version" => "candidate-impact-surface/v1",
          "surface_digest" => "sha256:#{'9' * 64}",
          "evidence_revision" => 1,
          "manifest_digest" => manifest_digest,
          "build_context_digest" => build_context_digest,
          "produces" => [
            {
              "impact_key" => "contract:payments-api:v2",
              "before" => nil,
              "after" => "available"
            }
          ],
          "consumes" => [],
          "may_affect" => [],
          "assumes" => [],
          "analyzer" => {
            "kind" => "agent",
            "id" => "analyzer-7",
            "analyzer_version" => "factory-v1"
          },
          "evidence_status" => "attributed_unverified"
        }
      end
      impact_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "CandidateImpactSurfaceDerived",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "Candidate",
          "stream_id" => candidate_id,
          "stream_revision" => 3
        }
      end
      impact_actor { submitted_actor }
      impact_markers { submitted_markers }
      impact_metadata { { "schema_version" => 1 } }
      impact_global_position { submitted_global_position + 3 }
      impact_at_domain { submitted_at_domain + 3.seconds }
      impact_at_store { submitted_at_store + 3.seconds }
    end
  end
end
