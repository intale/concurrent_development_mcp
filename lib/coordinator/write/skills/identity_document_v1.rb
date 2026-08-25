# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class IdentityDocumentV1 < Value
      SCHEMA = "skill-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :name, Types::SkillName
      attribute :scope, Types::SkillScope
    end
  end
end
