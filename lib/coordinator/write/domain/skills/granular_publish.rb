# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Skills
      # Builds the cohesive facts for one high-level skill_publish command.
      # The caller supplies stream references and generated UUIDv7 identities;
      # persistence of all returned writes belongs to Client#multiple.
      class GranularPublish
        include Dry::Monads[:result]

        class DecisionV1 < Value
          attribute :event_plan, Types.Instance(EventPlan).optional
          attribute :publication, Types.Instance(Events::SkillRevisionPublishedV3).optional
          attribute :skill_revision_id, Types::UuidV7
          attribute :revision, Types::SkillRevision
          attribute :outcome, Types::String.enum("published", "existing")
        end

        def call(state:, command:, skill_stream:, revision_stream:, asset_streams:, revision_id:)
          identity_failure = identity_conflict(state, command)
          return identity_failure if identity_failure

          current_revision = state.revision || 0
          return revision_conflict(state, command) unless current_revision == command.expected_revision
          if state.content_digest == command.content_digest && state.skill_revision_id
            return Success(
              DecisionV1.new(
                event_plan: nil,
                publication: nil,
                skill_revision_id: state.skill_revision_id,
                revision: current_revision,
                outcome: "existing"
              )
            )
          end

          revision = current_revision + 1
          assets = command.assets
          return invalid_assets(assets.length, asset_streams.length) unless assets.length == asset_streams.length

          writes = []
          if state.name.nil?
            writes << EventWrite.new(
              stream: skill_stream,
              event: Events::SkillRegisteredV1.new(
                skill_id: command.skill_id,
                name: command.name,
                scope: command.scope
              )
            )
          end

          writes << EventWrite.new(
            stream: revision_stream,
            event: Events::SkillRevisionCreatedV1.new(
              skill_revision_id: revision_id,
              skill_id: command.skill_id,
              revision:
            )
          )
          writes << EventWrite.new(
            stream: revision_stream,
            event: Events::SkillRevisionDescriptionDefinedV1.new(
              skill_revision_id: revision_id,
              description: command.description
            )
          )
          writes << EventWrite.new(
            stream: revision_stream,
            event: Events::SkillRevisionInstructionsDefinedV1.new(
              skill_revision_id: revision_id,
              instructions: command.instructions
            )
          )

          assets.zip(asset_streams).each do |asset, asset_stream|
            asset_id = asset_stream.stream_id
            writes.concat(asset_writes(asset:, asset_id:, asset_stream:, revision_stream:, revision_id:, skill_id: command.skill_id, revision:))
          end

          publication = Events::SkillRevisionPublishedV3.new(
            skill_id: command.skill_id,
            skill_revision_id: revision_id,
            revision:
          )
          writes << EventWrite.new(
            stream: skill_stream,
            event: publication
          )

          Success(
            DecisionV1.new(
              event_plan: EventPlan.new(writes:),
              publication:,
              skill_revision_id: revision_id,
              revision:,
              outcome: "published"
            )
          )
        end

        private

        def asset_writes(asset:, asset_id:, asset_stream:, revision_stream:, revision_id:, skill_id:, revision:)
          content = asset.content
          [
            EventWrite.new(
              stream: asset_stream,
              event: Events::SkillAssetCreatedV1.new(asset_id:)
            ),
            EventWrite.new(
              stream: asset_stream,
              event: Events::SkillAssetPathDefinedV1.new(asset_id:, path: asset.path)
            ),
            EventWrite.new(
              stream: asset_stream,
              event: Events::SkillAssetContentDefinedV1.new(
                asset_id:,
                content: content.respond_to?(:text) ? content.text : content.base64
              )
            ),
            EventWrite.new(
              stream: asset_stream,
              event: Events::SkillAssetExecutabilityDefinedV1.new(asset_id:, executable: asset.executable)
            ),
            EventWrite.new(
              stream: revision_stream,
              event: Events::SkillAssetAddedToRevisionV1.new(
                skill_revision_id: revision_id,
                skill_id:,
                revision:,
                asset_id:
              )
            )
          ]
        end

        def invalid_assets(expected, received)
          Failure(
            OutcomeError.new(
              code: :skill_asset_identity_invalid,
              message: "Skill asset stream count does not match the command assets",
              details: { expected:, received: }
            )
          )
        end

        def identity_conflict(state, command)
          return unless state.name
          return if state.skill_id == command.skill_id && state.name == command.name && state.scope == command.scope

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
                current_revision: state.revision || 0
              }
            )
          )
        end
      end
    end
  end
end
