# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class RevisionContentV2 < Value
      Asset = Types.Instance(AssetV2)

      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
      attribute :content_digest, Types::Sha256Digest
    end
  end
end
