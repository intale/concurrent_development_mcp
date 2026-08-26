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

          relation_id = artifact_relation.relation_id
          existing_declaration = state.relation(relation_id)
          if (supersession = state.supersession_for(relation_id))
            return replacement_superseded(artifact_relation, supersession)
          end

          superseded_relation_id = command.supersedes_relation_id
          if superseded_relation_id == relation_id
            return self_supersession(artifact_relation)
          end

          previous_declaration = superseded_relation_id && state.relation(superseded_relation_id)
          if superseded_relation_id && !previous_declaration
            return superseded_relation_missing(artifact_relation, superseded_relation_id)
          end

          previous_supersession = superseded_relation_id && state.supersession_for(superseded_relation_id)
          if previous_supersession
            return existing_supersession(existing_declaration, previous_supersession) if
              previous_supersession.replacement_relation_id == relation_id

            return already_superseded(artifact_relation, previous_supersession)
          end

          if !existing_declaration && state.relations.length >= Types::DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT
            return relation_limit_reached(artifact_relation.source_artifact_id, state.relations.length)
          end

          declaration = existing_declaration || Events::DevelopmentArtifactRelationDeclaredV1.new(
            artifact_relation:, declared_at:
          )
          supersession = if superseded_relation_id
            Events::DevelopmentArtifactRelationSupersededV1.new(
              source_artifact_id: artifact_relation.source_artifact_id,
              superseded_relation_id:,
              replacement_relation_id: relation_id,
              reason: command.supersession_reason,
              superseded_at: declared_at
            )
          end
          events = []
          events << declaration unless existing_declaration
          events << supersession if supersession
          Success(
            RelationDecisionV1.new(
              declaration:,
              supersession:,
              event_plan: events.empty? ? nil : event_plan(artifact_relation.source_artifact_id, events),
              outcome: supersession ? "superseded" : existing_declaration ? "existing" : "declared"
            )
          )
        end

        private

        def event_plan(artifact_id, events)
          stream = @stream_factory.development_artifact(artifact_id)
          EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) })
        end

        def existing_supersession(declaration, supersession)
          Success(
            RelationDecisionV1.new(
              declaration:,
              supersession:,
              event_plan: nil,
              outcome: "existing"
            )
          )
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

        def superseded_relation_missing(artifact_relation, superseded_relation_id)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_not_found,
              message: "Superseded Development Artifact relation was not found",
              details: {
                artifact_id: artifact_relation.source_artifact_id,
                relation_id: superseded_relation_id
              }
            )
          )
        end

        def self_supersession(artifact_relation)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_self_supersession,
              message: "A Development Artifact relation cannot supersede itself",
              details: { relation_id: artifact_relation.relation_id }
            )
          )
        end

        def replacement_superseded(artifact_relation, supersession)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_superseded,
              message: "A superseded Development Artifact relation cannot be a replacement",
              details: {
                relation_id: artifact_relation.relation_id,
                replacement_relation_id: supersession.replacement_relation_id
              }
            )
          )
        end

        def already_superseded(artifact_relation, supersession)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_already_superseded,
              message: "Development Artifact relation already has another replacement",
              details: {
                relation_id: supersession.superseded_relation_id,
                existing_replacement_relation_id: supersession.replacement_relation_id,
                requested_replacement_relation_id: artifact_relation.relation_id
              }
            )
          )
        end
      end
    end
  end
end
