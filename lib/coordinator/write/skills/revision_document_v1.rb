# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class RevisionDocumentV1 < Value
      SCHEMA = "skill-revision-content/v1"
      Asset = Types.Instance(AssetV1)

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
    end
  end
end
