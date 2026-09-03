# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class RevisionStateV1 < Value
      attribute :skill_revision_id, Types::UuidV7
      attribute :skill_id, Types::SkillId
      attribute :revision, Types::SkillRevision
      attribute :description, Types::SkillDescription.optional
      attribute :instructions, Types::SkillInstructions.optional
      attribute :asset_ids, Types::Array.of(Types::UuidV7)

      def self.initial(skill_revision_id:, skill_id:, revision:)
        new(
          skill_revision_id:,
          skill_id:,
          revision:,
          description: nil,
          instructions: nil,
          asset_ids: []
        )
      end

      def self.reduce(events)
        state = nil
        events.each do |event|
          case event
          when Events::SkillRevisionCreatedV1
            state = initial(
              skill_revision_id: event.skill_revision_id,
              skill_id: event.skill_id,
              revision: event.revision
            )
          when Events::SkillRevisionDescriptionDefinedV1
            state = state.class.new(**state.to_h, description: event.description)
          when Events::SkillRevisionInstructionsDefinedV1
            state = state.class.new(**state.to_h, instructions: event.instructions)
          when Events::SkillAssetAddedToRevisionV1
            state = state.class.new(**state.to_h, asset_ids: (state.asset_ids + [ event.asset_id ]).uniq)
          end
        end
        state
      end
    end
  end
end
