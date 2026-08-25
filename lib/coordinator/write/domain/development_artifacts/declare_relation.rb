# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class DeclareRelation
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, target_captured:, declared_at:)
          artifact_relation = command.artifact_relation
          return artifact_missing(artifact_relation.source_artifact_id) unless state.capture
          if artifact_relation.target.kind == "artifact" && !target_captured
            return target_missing(artifact_relation)
          end

          existing = state.relations.find do |event|
            event.artifact_relation.relation_id == artifact_relation.relation_id
          end
          return existing(existing) if existing
          if state.relations.length >= Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
            return relation_limit_reached(artifact_relation.source_artifact_id, state.relations.length)
          end

          event = Events::DevelopmentArtifactRelationDeclaredV1.new(
            artifact_relation:,
            declared_at:
          )
          Success(
            RelationDecisionV1.new(
              declaration: event,
              event_plan: EventPlan.new(
                writes: [
                  EventWrite.new(
                    stream: @stream_factory.development_artifact(artifact_relation.source_artifact_id),
                    event:
                  )
                ]
              ),
              outcome: "declared"
            )
          )
        end

        private

        def existing(declaration)
          Success(RelationDecisionV1.new(declaration:, event_plan: nil, outcome: "existing"))
        end

        def artifact_missing(artifact_id)
          Failure(
            OutcomeError.new(
              code: :development_artifact_not_found,
              message: "Source Development Artifact was not found",
              details: { artifact_id: }
            )
          )
        end

        def target_missing(artifact_relation)
          Failure(
            OutcomeError.new(
              code: :development_artifact_target_not_found,
              message: "Target Development Artifact was not found",
              details: {
                artifact_id: artifact_relation.source_artifact_id,
                target_artifact_id: artifact_relation.target.id
              }
            )
          )
        end

        def relation_limit_reached(artifact_id, relation_count)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_limit_reached,
              message: "Development Artifact relation limit was reached",
              details: {
                artifact_id:,
                relation_count:,
                maximum_relation_count: Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
              }
            )
          )
        end
      end
    end
  end
end
