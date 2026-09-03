# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class SkillStateV1 < Value
      attribute :skill_id, Types::SkillId
      attribute :name, Types::SkillName.optional
      attribute :scope, Types::SkillScope.optional
      attribute :skill_revision_id, Types::UuidV7.optional
      attribute :revision, Types::SkillRevision.optional
      attribute :content_digest, Types::Sha256Digest.optional

      def self.initial(skill_id:)
        new(skill_id:, name: nil, scope: nil, skill_revision_id: nil, revision: nil, content_digest: nil)
      end

      def self.reduce(events)
        state = nil
        events.each do |event|
          case event
          when Events::SkillRegisteredV1
            state = new(
              skill_id: event.skill_id,
              name: event.name,
              scope: event.scope,
              skill_revision_id: nil,
              revision: nil,
              content_digest: nil
            )
          when Events::SkillRevisionPublishedV3
            state = state.class.new(
              **state.to_h,
              skill_revision_id: event.skill_revision_id,
              revision: event.revision
            )
          end
        end
        state
      end
    end
  end
end
