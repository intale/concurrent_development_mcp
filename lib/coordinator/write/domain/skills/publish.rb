# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Skills
      class Publish
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, published_at:)
          conflict = identity_conflict(state, command)
          return conflict if conflict
          return revision_conflict(state, command) unless state.current_revision == command.expected_revision

          event = Events::SkillRevisionPublishedV1.new(
            skill_id: command.skill_id,
            name: command.name,
            scope: command.scope,
            revision: state.current_revision + 1,
            description: command.description,
            instructions: command.instructions,
            assets: command.assets,
            content_digest: command.content_digest,
            published_at:
          )
          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(stream: @stream_factory.skill(command.skill_id), event:)
              ]
            )
          )
        end

        private

        def identity_conflict(state, command)
          publication = state.publication
          return unless publication
          return if publication.skill_id == command.skill_id &&
                    publication.name == command.name && publication.scope == command.scope

          Failure(
            OutcomeError.new(
              code: :skill_identity_conflict,
              message: "Skill stream identity does not match the requested name and scope",
              details: { skill_id: command.skill_id, name: command.name, scope: command.scope }
            )
          )
        end

        def revision_conflict(state, command)
          Failure(
            OutcomeError.new(
              code: :skill_revision_conflict,
              message: "Skill revision changed; retrieve the current revision and retry",
              details: {
                skill_id: command.skill_id,
                name: command.name,
                scope: command.scope,
                expected_revision: command.expected_revision,
                current_revision: state.current_revision
              }
            )
          )
        end
      end
    end
  end
end
