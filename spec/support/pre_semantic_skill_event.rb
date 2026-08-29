# frozen_string_literal: true

module PreSemanticSkillEvent
  module_function

  def build(identity:, content: "legacy text\n", content_sha256: nil, command_id: "cmd-pre-semantic-skill")
    bytes = content.b
    content_sha256 ||= "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}"

    PgEventstore::Event.new(
      id: SecureRandom.uuid_v7,
      type: "SkillRevisionPublished",
      data: {
        "skill_id" => identity.skill_id,
        "name" => identity.name,
        "scope" => identity.scope,
        "revision" => 1,
        "description" => "Pre-semantic Skill",
        "instructions" => "Preserve and normalize this Skill.",
        "assets" => [
          {
            "path" => "references/legacy.txt",
            "media_type" => "text/plain",
            "executable" => false,
            "content_base64" => [ bytes ].pack("m0"),
            "content_sha256" => content_sha256,
            "byte_size" => bytes.bytesize
          }
        ],
        "content_digest" => "sha256:#{'1' * 64}",
        "published_at" => "2026-08-25T12:00:00.000000Z"
      },
      metadata: {
        "schema_version" => 1,
        "command_id" => command_id,
        "actor_kind" => "agent",
        "actor_id" => "pre-semantic-importer",
        "recorded_by" => "coordinator",
        "policy_version" => "skill-repository/v1"
      }
    )
  end
end
