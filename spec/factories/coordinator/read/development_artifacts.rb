# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_development_artifact,
          class: "Coordinator::Read::DevelopmentArtifact" do
    artifact_id { SecureRandom.uuid_v7 }
    scope { "project:factory" }
    sequence(:title) { "Factory artifact #{_1}" }
    kind { "documentation" }
    labels { %w[factory documentation] }
    content_encoding { "utf-8" }
    content_media_type { "text/markdown" }
    content_text { "# Factory artifact\n\nProjected content." }
    content_base64 { nil }
    content_sha256 { "sha256:#{'a' * 64}" }
    content_byte_size { content_text.bytesize }
    source_kind { "local_file" }
    sequence(:source_locator) { "docs/factory-#{_1}.md" }
    source_revision { "a" * 40 }
    source_observed_at { Time.utc(2026, 8, 30, 11, 59) }
    source_collector { "factory-collector/v1" }
    captured_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DevelopmentArtifactCreated",
        "stream_context" => "DevelopmentMemory",
        "stream_name" => "DevelopmentArtifact",
        "stream_id" => artifact_id,
        "stream_revision" => 0
      }
    end
    captured_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    captured_markers { [ "development-artifact:#{artifact_id}" ] }
    captured_metadata { { "schema_version" => 1 } }
    sequence(:captured_global_position, 800)
    stream_revision { 0 }
    captured_at_domain { Time.utc(2026, 8, 30, 12) }
    captured_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }

    trait :binary do
      content_encoding { "binary" }
      content_media_type { "application/octet-stream" }
      content_text { nil }
      content_base64 { "ZmFjdG9yeQ==" }
      content_byte_size { 7 }
    end
  end

  factory :coordinator_read_development_artifact_observation,
          class: "Coordinator::Read::DevelopmentArtifactObservation" do
    association :artifact, factory: :coordinator_read_development_artifact
    observation_id { SecureRandom.uuid_v7 }
    artifact_id { artifact.artifact_id }
    scope { artifact.scope }
    title { artifact.title }
    kind { artifact.kind }
    labels { artifact.labels }
    source_kind { artifact.source_kind }
    source_locator { artifact.source_locator }
    source_revision { artifact.source_revision }
    source_observed_at { artifact.source_observed_at }
    source_collector { artifact.source_collector }
    content_encoding { artifact.content_encoding }
    content_media_type { artifact.content_media_type }
    content_text { artifact.content_text }
    content_base64 { artifact.content_base64 }
    content_sha256 { artifact.content_sha256 }
    content_byte_size { artifact.content_byte_size }
    classification_revision { 1 }
    classification_reason { nil }
    observed_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DevelopmentArtifactObservationRecorded",
        "stream_context" => "DevelopmentMemory",
        "stream_name" => "DevelopmentArtifactObservation",
        "stream_id" => observation_id,
        "stream_revision" => 0
      }
    end
    observed_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    observed_markers { [ "development-artifact-observation:#{observation_id}" ] }
    observed_metadata { { "schema_version" => 1 } }
    sequence(:observed_global_position, 900)
    observed_at_domain { Time.utc(2026, 8, 30, 12, 1) }
    observed_at_store { Time.utc(2026, 8, 30, 12, 1, 1) }
    classified_event { observed_event }
    classified_actor { observed_actor }
    classified_markers { observed_markers }
    classified_metadata { observed_metadata }
    classified_global_position { observed_global_position }
    classified_at_domain { observed_at_domain }
    classified_at_store { observed_at_store }
    current_global_position { [ observed_global_position, classified_global_position ].compact.max }
    sequence(:observed_sequence, 1)

    fact_links do
      facts = {
        "created" => [ "DevelopmentArtifactCreated", {} ],
        "scope" => [ "DevelopmentArtifactScopeChanged", { "scope" => scope } ],
        "title" => [ "DevelopmentArtifactTitleChanged", { "title" => title } ],
        "kind" => [ "DevelopmentArtifactKindChanged", { "kind" => kind } ],
        "source" => [ "DevelopmentArtifactSourceChanged", {
          "source_kind" => source_kind, "locator" => source_locator,
          "revision" => source_revision, "observed_at" => source_observed_at.utc.iso8601(6)
        } ],
        "content" => [ "DevelopmentArtifactContentChanged", {
          "content" => content_encoding == "utf-8" ? content_text : content_base64
        } ]
      }
      facts.map.with_index do |(role, (type, data)), index|
        association(
          :coordinator_read_development_artifact_observation_fact_link,
          strategy: :build,
          observation: nil,
          observation_id:,
          artifact_id:,
          role:,
          observed_fact_event: {
            "event_id" => SecureRandom.uuid_v7, "type" => type,
            "stream_context" => "DevelopmentMemory", "stream_name" => "DevelopmentArtifact",
            "stream_id" => artifact_id, "stream_revision" => index
          },
          observed_fact_data: { "artifact_id" => artifact_id, **data }
        )
      end
    end
  end

  factory :coordinator_read_development_artifact_observation_fact_link,
          class: "Coordinator::Read::DevelopmentArtifactObservationFactLink" do
    association :observation, factory: :coordinator_read_development_artifact_observation
    link_event_id { SecureRandom.uuid_v7 }
    observation_id { observation.observation_id }
    artifact_id { observation.artifact_id }
    role { "title" }
    link_event do
      {
        "event_id" => link_event_id,
        "type" => "DevelopmentArtifactObservationFactLinked",
        "stream_context" => "DevelopmentMemory",
        "stream_name" => "DevelopmentArtifactObservation",
        "stream_id" => observation_id,
        "stream_revision" => 1
      }
    end
    link_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    link_markers { [ "development-artifact-observation:#{observation_id}" ] }
    link_metadata { { "schema_version" => 1 } }
    link_global_position { 950 }
    link_at_domain { Time.utc(2026, 8, 30, 12, 1, 1) }
    link_at_store { Time.utc(2026, 8, 30, 12, 1, 2) }
    observed_fact_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DevelopmentArtifactTitleChanged",
        "stream_context" => "DevelopmentMemory",
        "stream_name" => "DevelopmentArtifact",
        "stream_id" => artifact_id,
        "stream_revision" => 1
      }
    end
    observed_fact_event_id { observed_fact_event.fetch("event_id") }
    observed_fact_data { { "artifact_id" => artifact_id, "title" => "Factory artifact" } }
    observed_fact_metadata { { "schema_version" => 1 } }
    observed_fact_created_at { Time.utc(2026, 8, 30, 12, 1) }
  end

  factory :coordinator_read_development_artifact_relation,
          class: "Coordinator::Read::DevelopmentArtifactRelation" do
    association :source_artifact, factory: :coordinator_read_development_artifact
    relation_id { SecureRandom.uuid_v7 }
    source_artifact_id { source_artifact.artifact_id }
    relation { "references" }
    target_kind { "artifact" }
    target_id { SecureRandom.uuid_v7 }
    target_status { "verified" }
    target_name { nil }
    target_scope { nil }
    path { nil }
    fragment { nil }
    normalized_locator { nil }
    declared_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DevelopmentArtifactRelationDeclared",
        "stream_context" => "DevelopmentMemory",
        "stream_name" => "DevelopmentArtifact",
        "stream_id" => source_artifact_id,
        "stream_revision" => 1
      }
    end
    declared_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    declared_markers { [ "development-artifact-relation:#{relation_id}" ] }
    declared_metadata { { "schema_version" => 1 } }
    sequence(:declared_global_position, 1_000)
    declared_at_domain { Time.utc(2026, 8, 30, 12, 2) }
    declared_at_store { Time.utc(2026, 8, 30, 12, 2, 1) }
  end

  factory :coordinator_read_development_artifact_relation_supersession,
          class: "Coordinator::Read::DevelopmentArtifactRelationSupersession" do
    association :relation, factory: :coordinator_read_development_artifact_relation
    superseded_relation_id { relation.relation_id }
    source_artifact_id { relation.source_artifact_id }
    replacement_relation_id { SecureRandom.uuid_v7 }
    reason { "A more precise relation replaced this one." }
    superseded_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DevelopmentArtifactRelationSuperseded",
        "stream_context" => "DevelopmentMemory",
        "stream_name" => "DevelopmentArtifact",
        "stream_id" => source_artifact_id,
        "stream_revision" => 2
      }
    end
    superseded_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    superseded_markers { [ "development-artifact-relation:#{superseded_relation_id}" ] }
    superseded_metadata { { "schema_version" => 1 } }
    sequence(:superseded_global_position, 1_100)
    superseded_at_domain { Time.utc(2026, 8, 30, 12, 3) }
    superseded_at_store { Time.utc(2026, 8, 30, 12, 3, 1) }
  end
end
