# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_skill, class: "Coordinator::Read::Skill" do
    sequence(:skill_id) { "skill:v1:#{format('%064x', _1)}" }
    sequence(:name) { "factory-skill-#{_1}" }
    scope { "project:factory" }
    revision { 1 }
  end

  factory :coordinator_read_skill_revision, class: "Coordinator::Read::SkillRevision" do
    association :skill, factory: :coordinator_read_skill
    skill_id { skill.skill_id }
    revision { skill.revision }
    description { "A projected Skill fixture." }
    instructions { "Use the projected read-side instructions." }
    content_digest { "sha256:#{'1' * 64}" }
    asset_count { 0 }
    published_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "SkillRevisionPublished",
        "stream_context" => "DevelopmentKnowledge",
        "stream_name" => "Skill",
        "stream_id" => skill_id,
        "stream_revision" => revision - 1
      }
    end
    published_actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    published_markers { [ "skill:#{skill_id}" ] }
    published_metadata { { "schema_version" => 1 } }
    sequence(:published_global_position, 500)
    published_at_domain { Time.utc(2026, 8, 30, 12) + revision.seconds }
    published_at_store { published_at_domain + 1.second }
  end

  factory :coordinator_read_skill_asset, class: "Coordinator::Read::SkillAsset" do
    association :skill, factory: :coordinator_read_skill
    skill_id { skill.skill_id }
    revision { skill.revision }
    sequence(:path) { "fixtures/factory-#{_1}.txt" }
    media_type { "text/plain" }
    executable { false }
    content_encoding { "utf-8" }
    content_text { "factory content" }
    content_base64 { nil }
    content_sha256 { "sha256:#{'2' * 64}" }
    byte_size { content_text.bytesize }

    trait :binary do
      media_type { "application/octet-stream" }
      content_encoding { "binary" }
      content_text { nil }
      content_base64 { "ZmFjdG9yeQ==" }
      byte_size { 7 }
    end
  end
end
