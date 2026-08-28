# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class DeclareRelation
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          relation_registry: Coordinator::Write::DevelopmentArtifacts::RelationRegistry.new
        )
          @stream_factory = stream_factory
          @relation_registry = relation_registry
        end

        def call(state:, command:, target:, declared_at:)
          artifact_relation = command.artifact_relation.with_target(target)
          return artifact_missing(artifact_relation.source_artifact_id) unless state.capture

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

          if previous_declaration && !supersession_allowed?(previous_declaration, artifact_relation)
            return supersession_not_allowed(artifact_relation, previous_declaration)
          end

          previous_supersession = superseded_relation_id && state.supersession_for(superseded_relation_id)
          if previous_supersession
            return existing_supersession(existing_declaration, previous_supersession) if
              previous_supersession.replacement_relation_id == relation_id

            return already_superseded(artifact_relation, previous_supersession)
          end

          unless existing_declaration
            lifetime_count = state.relations.length
            if lifetime_count >= Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT
              return relation_limit_reached(
                artifact_relation.source_artifact_id,
                state:,
                limit_kind: "lifetime"
              )
            end

            active_count = state.active_relations.length
            active_after = active_count + 1 - (previous_declaration ? 1 : 0)
            if active_after > Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT
              return relation_limit_reached(
                artifact_relation.source_artifact_id,
                state:,
                limit_kind: "active"
              )
            end
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

        def supersession_allowed?(previous_declaration, artifact_relation)
          previous = previous_declaration.artifact_relation
          previous.relation == artifact_relation.relation &&
            @relation_registry.fetch(previous.relation).supersedable
        end

        def relation_limit_reached(artifact_id, state:, limit_kind:)
          active_count = state.active_relations.length
          lifetime_count = state.relations.length
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_limit_reached,
              message: "Development Artifact #{limit_kind} relation limit was reached",
              details: {
                artifact_id:,
                limit_kind:,
                active_count:,
                active_maximum: Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
                active_remaining: [
                  Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT - active_count,
                  0
                ].max,
                lifetime_count:,
                lifetime_maximum: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT,
                lifetime_remaining: [
                  Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT - lifetime_count,
                  0
                ].max
              }
            )
          )
        end

        def supersession_not_allowed(artifact_relation, previous_declaration)
          previous = previous_declaration.artifact_relation
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_supersession_not_allowed,
              message: "Development Artifact relation cannot supersede this edge",
              details: {
                artifact_id: artifact_relation.source_artifact_id,
                relation_id: previous.relation_id,
                relation: previous.relation,
                requested_relation: artifact_relation.relation
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
              details: {
                artifact_id: artifact_relation.source_artifact_id,
                relation_id: artifact_relation.relation_id
              }
            )
          )
        end

        def replacement_superseded(artifact_relation, supersession)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_superseded,
              message: "A superseded Development Artifact relation cannot be a replacement",
              details: {
                artifact_id: artifact_relation.source_artifact_id,
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
                artifact_id: artifact_relation.source_artifact_id,
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
