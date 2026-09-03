# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      # A relation is an entity in its own stream. Supersession is written to the
      # superseded relation stream, never into the source Artifact stream.
      class DeclareRelationV2
        include Dry::Monads[:result]

        def initialize(
          stream_factory: StreamFactory.new,
          relation_registry: Coordinator::Shared::DevelopmentArtifactRelationRegistry.new
        )
          @stream_factory = stream_factory
          @relation_registry = relation_registry
        end

        def call(
          relation:,
          source_relations: [],
          superseded_state: nil,
          superseded_relation_id: nil,
          supersession_reason: nil
        )
          existing = source_relations.find do |state|
            declaration = state.declaration
            declaration && declaration.source_artifact_id == relation.source_artifact_id &&
              declaration.relation == relation.relation &&
              declaration.target_kind == relation.target.kind &&
              declaration.target_id == relation.target.id &&
              declaration.path == relation.relation_attributes.path &&
              declaration.fragment == relation.relation_attributes.fragment &&
              declaration.normalized_locator == relation.relation_attributes.normalized_locator
          end
          if existing
            return relation_superseded(relation, existing) if existing.supersession

            return Success(DeclareRelationV2Decision.new(
              relation_id: existing.declaration.relation_id,
              source_artifact_id: relation.source_artifact_id,
              event_plan: nil,
              outcome: "existing"
            ))
          end

          if source_relations.length >= Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT
            return limit(relation, "lifetime", source_relations)
          end

          active_count = source_relations.count(&:active?)
          if superseded_relation_id
            return self_supersession(relation) if superseded_relation_id == relation.relation_id
            return missing_superseded(relation, superseded_relation_id) unless superseded_state&.declaration
            return already_superseded(relation, superseded_state) if superseded_state.supersession
            unless supersession_allowed?(superseded_state, relation)
              return supersession_not_allowed(relation, superseded_state)
            end
            active_count -= 1
          end
          return limit(relation, "active", source_relations) if active_count >= Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT

          writes = [
            EventWrite.new(
              stream: @stream_factory.development_artifact_relation(relation.relation_id),
              event: Events::DevelopmentArtifactRelationDeclaredV2.new(
                relation_id: relation.relation_id,
                source_artifact_id: relation.source_artifact_id,
                relation: relation.relation,
                target_kind: relation.target.kind,
                target_id: relation.target.id,
                path: relation.relation_attributes.path,
                fragment: relation.relation_attributes.fragment,
                normalized_locator: relation.relation_attributes.normalized_locator
              )
            )
          ]
          if superseded_relation_id
            writes << EventWrite.new(
              stream: @stream_factory.development_artifact_relation(superseded_relation_id),
              event: Events::DevelopmentArtifactRelationSupersededV2.new(
                relation_id: superseded_relation_id,
                source_artifact_id: relation.source_artifact_id,
                replacement_relation_id: relation.relation_id,
                reason: supersession_reason
              )
            )
          end

          Success(
            DeclareRelationV2Decision.new(
              relation_id: relation.relation_id,
              source_artifact_id: relation.source_artifact_id,
              event_plan: EventPlan.new(writes:),
              outcome: superseded_relation_id ? "superseded" : "declared"
            )
          )
        end

        private

        def supersession_allowed?(state, relation)
          declaration = state.declaration
          declaration.source_artifact_id == relation.source_artifact_id &&
            declaration.relation == relation.relation &&
            @relation_registry.fetch(relation.relation).supersedable
        end

        def self_supersession(relation)
          failure(:development_artifact_relation_self_supersession, "A relation cannot supersede itself", relation)
        end

        def missing_superseded(relation, relation_id)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_not_found,
              message: "Superseded relation was not found",
              details: {
                artifact_id: relation.source_artifact_id,
                relation_id:
              }
            )
          )
        end

        def already_superseded(relation, state)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_already_superseded,
              message: "Relation already has a replacement",
              details: {
                artifact_id: relation.source_artifact_id,
                relation_id: state.declaration.relation_id,
                existing_replacement_relation_id: state.supersession.replacement_relation_id,
                requested_replacement_relation_id: relation.relation_id
              }
            )
          )
        end

        def supersession_not_allowed(relation, state)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_supersession_not_allowed,
              message: "Relation cannot be superseded",
              details: {
                artifact_id: relation.source_artifact_id,
                relation_id: state.declaration.relation_id,
                relation: state.declaration.relation,
                requested_relation: relation.relation
              }
            )
          )
        end

        def limit(relation, kind, source_relations)
          active_count = source_relations.count(&:active?)
          lifetime_count = source_relations.length
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_limit_reached,
              message: "Relation #{kind} limit was reached",
              details: {
                artifact_id: relation.source_artifact_id,
                limit_kind: kind,
                active_count:,
                active_maximum: Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT,
                active_remaining: [ Types::DEVELOPMENT_ARTIFACT_ACTIVE_RELATION_MAXIMUM_COUNT - active_count, 0 ].max,
                lifetime_count:,
                lifetime_maximum: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT,
                lifetime_remaining: [ Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT - lifetime_count, 0 ].max
              }
            )
          )
        end

        def relation_superseded(relation, state)
          Failure(
            OutcomeError.new(
              code: :development_artifact_relation_superseded,
              message: "A superseded relation cannot be used as an active declaration",
              details: {
                artifact_id: relation.source_artifact_id,
                relation_id: state.declaration.relation_id,
                replacement_relation_id: state.supersession.replacement_relation_id
              }
            )
          )
        end
      end
    end
  end
end
