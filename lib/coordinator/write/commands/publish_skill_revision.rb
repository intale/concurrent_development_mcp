# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class PublishSkillRevision < Value
      Asset = Types.Instance(Skills::AssetV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :expected_revision, Types::SkillExpectedRevision
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :content_digest, Types::Sha256Digest
    end
  end
end
