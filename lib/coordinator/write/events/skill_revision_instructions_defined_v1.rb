# frozen_string_literal: true

module Coordinator::Write
  module Events
    class SkillRevisionInstructionsDefinedV1 < Base
      contract type: "SkillRevisionInstructionsDefined", version: 1

      attribute :skill_revision_id, Types::UuidV7
      attribute :instructions, Types::SkillInstructions
    end
  end
end
