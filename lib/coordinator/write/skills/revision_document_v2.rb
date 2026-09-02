# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class RevisionDocumentV2 < Value
      SCHEMA = "skill-revision-content/v2"
      Asset = Types.Instance(AssetV2)

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
      attribute :description, Types::SkillDescription
      attribute :instructions, Types::SkillInstructions
      attribute :assets,
                Types::Array.of(Asset).constrained(max_size: Types::SKILL_ASSET_MAXIMUM_COUNT)
    end
  end
end
