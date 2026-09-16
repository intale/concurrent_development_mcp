# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionDocumentTransformer
      include Dry::Monads[:result]

      SCOPE_TARGETS = {
        repository_ids: [ "DevelopmentPlanning", "Repository", "repository" ],
        change_set_id: [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        work_item_id: [ "DevelopmentExecution", "WorkItem", "work-item" ],
        attempt_id: [ "DevelopmentExecution", "Attempt", "attempt" ],
        candidate_id: [ "DevelopmentIntegration", "Candidate", "candidate" ]
      }.freeze
      STREAM_TARGETS = {
        [ "DevelopmentPlanning", "Repository" ] => "repository",
        [ "DevelopmentPlanning", "ChangeSet" ] => "change-set",
        [ "DevelopmentExecution", "WorkItem" ] => "work-item",
        [ "DevelopmentExecution", "Attempt" ] => "attempt",
        [ "DevelopmentIntegration", "Candidate" ] => "candidate",
        [ "HumanGuidance", "Conversation" ] => "conversation",
        [ "HumanGuidance", "Interpretation" ] => "interpretation",
        [ "HumanGuidance", "Decision" ] => "decision"
      }.freeze

      def initialize(entity_reference_resolver:)
        @entity_reference_resolver = entity_reference_resolver
      end

      def proposed_decision(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        proposed_decision:
      )
        transformed = components(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          scope: proposed_decision.scope,
          relations: proposed_decision.relations,
          validity: proposed_decision.validity
        )
        return transformed if transformed.failure?

        scope, relations, validity = transformed.value!
        Success(
          Interpretations::ProposedDecisionV1.new(
            proposed_decision.to_h.merge(scope:, relations:, validity:)
          )
        )
      end

      def definition(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        definition:
      )
        document = definition.document
        transformed = components(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          scope: document.scope,
          relations: document.relations,
          validity: document.validity
        )
        return transformed if transformed.failure?

        scope, relations, validity = transformed.value!
        Success(
          Decisions::DecisionDefinitionDocumentV1.new(
            document.to_h.merge(scope:, relations:, validity:)
          )
        )
      end

      def slot_document(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        document:
      )
        scope = transform_scope(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          scope: document.exact_scope
        )
        return scope if scope.failure?

        Success(Decisions::DecisionSlotDocumentV1.new(document.to_h.merge(exact_scope: scope.value!)))
      end

      private

      def components(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        scope:,
        relations:,
        validity:
      )
        transformed_scope = transform_scope(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          scope:
        )
        return transformed_scope if transformed_scope.failure?

        transformed_relations = transform_relations(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          relations:
        )
        return transformed_relations if transformed_relations.failure?

        transformed_validity = transform_validity(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          validity:
        )
        return transformed_validity if transformed_validity.failure?

        Success([ transformed_scope.value!, transformed_relations.value!, transformed_validity.value! ])
      end

      def transform_scope(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        scope:
      )
        repositories = resolve_many(
          scope.repository_ids,
          target: SCOPE_TARGETS.fetch(:repository_ids),
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return repositories if repositories.failure?

        values = scope.to_h.merge(repository_ids: repositories.value!.sort_by(&:b))
        %i[change_set_id work_item_id attempt_id candidate_id].each do |attribute|
          source_id = scope.public_send(attribute)
          next unless source_id

          resolved = resolve_one(
            source_id,
            target: SCOPE_TARGETS.fetch(attribute),
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:
          )
          return resolved if resolved.failure?

          values[attribute] = resolved.value!
        end
        Success(Interpretations::DecisionScopeV1.new(values))
      end

      def transform_relations(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        relations:
      )
        values = {}
        %i[corrects supersedes exception_to revokes].each do |attribute|
          resolved = resolve_many(
            relations.public_send(attribute),
            target: [ "HumanGuidance", "Decision", "decision" ],
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:
          )
          return resolved if resolved.failure?

          values[attribute] = resolved.value!.sort_by(&:b)
        end
        Success(Interpretations::DecisionRelationsV1.new(values))
      end

      def transform_validity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        validity:
      )
        condition = validity.until_event
        return Success(validity) unless condition

        identity_role = STREAM_TARGETS[[ condition.stream_context, condition.stream_name ]]
        return Success(validity) unless identity_role

        resolved = resolve_one(
          condition.stream_id,
          target: [ condition.stream_context, condition.stream_name, identity_role ],
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return resolved if resolved.failure?

        target_condition = Interpretations::UntilEventConditionV1.new(
          condition.to_h.merge(stream_id: resolved.value!)
        )
        Success(Interpretations::DecisionValidityV1.new(validity.to_h.merge(until_event: target_condition)))
      end

      def resolve_many(ids, target:, **context)
        resolved = []
        ids.each do |source_id|
          result = resolve_one(source_id, target:, **context)
          return result if result.failure?

          resolved << result.value!
        end
        Success(resolved.freeze)
      end

      def resolve_one(
        source_id,
        target:,
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:
      )
        allocation = @entity_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_stream: StreamReference.new(
            context: target.fetch(0),
            stream_name: target.fetch(1),
            stream_id: source_id
          ),
          target_stream_context: target.fetch(0),
          target_stream_name: target.fetch(1),
          identity_role: target.fetch(2)
        )
        return allocation if allocation.failure?

        Success(allocation.value!.target_stream.stream_id)
      end
    end
  end
end
