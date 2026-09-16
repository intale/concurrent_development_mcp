# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceDocumentTransformer
      include Dry::Monads[:result]

      QUERY_TARGETS = {
        repository_id: [ "DevelopmentPlanning", "Repository", "repository" ],
        change_set_id: [ "DevelopmentPlanning", "ChangeSet", "change-set" ],
        work_item_id: [ "DevelopmentExecution", "WorkItem", "work-item" ],
        attempt_id: [ "DevelopmentExecution", "Attempt", "attempt" ]
      }.freeze

      def initialize(
        event_store:,
        entity_reference_resolver:,
        partition_identity_mapper:,
        partition_delta_resolver:,
        head_reference_resolver:,
        target_event_reference_resolver:,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @entity_reference_resolver = entity_reference_resolver
        @partition_identity_mapper = partition_identity_mapper
        @partition_delta_resolver = partition_delta_resolver
        @head_reference_resolver = head_reference_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @canonical_json = canonical_json
      end

      def query_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:
      )
        identifiers = {}
        QUERY_TARGETS.each do |attribute, target|
          resolution = resolve_entity(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_id: context.public_send(attribute),
            target:
          )
          return resolution if resolution.failure?

          identifiers[attribute] = resolution.value!
        end

        Success(DecisionContexts::QueryContextV1.new(context.to_h.merge(identifiers)))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "AgentChoice query context is invalid: #{error.message}"))
      end

      def decision_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        context:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        query = query_context(**common, context: context.document.query_context)
        return query if query.failure?

        partitions = transform_many(context.document.partitions) do |observation|
          partition_observation(**common, observation:)
        end
        return partitions if partitions.failure?

        effective = transform_optional(context.document.effective_decision) do |decision|
          resolved_decision(**common, decision:)
        end
        return effective if effective.failure?

        shadowed = transform_many(context.document.shadowed_decisions) do |decision|
          shadowed_decision(**common, decision:)
        end
        return shadowed if shadowed.failure?

        conflict = transform_optional(context.document.conflict) do |value|
          conflict(**common, conflict: value)
        end
        return conflict if conflict.failure?

        document = DecisionContexts::ContextDocumentV1.new(
          context.document.to_h.merge(
            query_context: query.value!,
            partitions: partitions.value!,
            effective_decision: effective.value!,
            shadowed_decisions: shadowed.value!,
            conflict: conflict.value!
          )
        )
        Success(
          DecisionContexts::ContextV1.new(
            document:,
            digest: @canonical_json.sha256(document.to_h),
            resolved_at: context.resolved_at
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "AgentChoice Decision context is invalid: #{error.message}"))
      end

      def choice_assessment(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        assessment:
      )
        decisions = transform_many(assessment.based_on_decisions) do |head|
          resolve_head(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            head:
          )
        end
        return decisions if decisions.failure?

        Success(AgentChoices::ChoiceAssessmentV1.new(assessment.to_h.merge(based_on_decisions: decisions.value!)))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "AgentChoice assessment is invalid: #{error.message}"))
      end

      private

      def partition_observation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        observation:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        partition = @partition_identity_mapper.call(**common, partition: observation.partition)
        return partition if partition.failure?

        decisions = transform_many(observation.active_decisions) do |head|
          resolve_head(**common, head:)
        end
        return decisions if decisions.failure?

        reference = partition_reference(
          **common,
          observation:,
          target_partition: partition.value!
        )
        return reference if reference.failure?

        target_reference = reference.value!
        Success(
          DecisionContexts::PartitionObservationV1.new(
            partition: partition.value!,
            partition_revision: target_reference&.stream_revision,
            event: target_reference,
            active_decisions: decisions.value!
          )
        )
      end

      def partition_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        observation:,
        target_partition:
      )
        unless observation.event
          return Success(nil) unless observation.partition_revision

          return Failure(inconsistent(source_event, "partition revision has no source event"))
        end

        persisted = locate(observation.event)
        unless persisted && persisted.id == observation.event.event_id &&
            persisted.type == observation.event.type && persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "partition observation source event is absent"))
        end

        delta = @partition_delta_resolver.call(
          source_event: persisted,
          source_upper_position:
        )
        return delta if delta.failure?

        source_partition = delta.value!.source_payload
        unless source_partition.partition == observation.partition &&
            source_partition.partition_revision == observation.partition_revision &&
            source_partition.active_decisions == observation.active_decisions
          return Failure(inconsistent(source_event, "partition observation differs from its source event"))
        end

        step_name, event_type, target_revision = partition_target(delta.value!)
        target = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: observation.event,
          target_stream: StreamReference.new(
            context: "HumanGuidance",
            stream_name: "DecisionPartition",
            stream_id: target_partition.partition_id
          ),
          target_event_type: event_type,
          target_step_name: step_name
        )
        return target if target.failure?
        unless target.value!.stream_revision == target_revision
          return Failure(inconsistent(source_event, "partition observation target revision is inconsistent"))
        end

        target
      end

      def partition_target(delta)
        if delta.add
          [
            "add-decision-to-partition",
            "DecisionAddedToPartition",
            delta.first_target_revision + (delta.remove ? 1 : 0)
          ]
        else
          [ "remove-decision-from-partition", "DecisionRemovedFromPartition", delta.first_target_revision ]
        end
      end

      def resolved_decision(**context)
        decision = context.fetch(:decision)
        head = resolve_head(**context.except(:decision), head: decision.head)
        return head if head.failure?

        Success(DecisionContexts::ResolvedDecisionV1.new(decision.to_h.merge(head: head.value!)))
      end

      def shadowed_decision(**context)
        source = context.fetch(:decision)
        decision = resolved_decision(**context.except(:decision), decision: source.decision)
        return decision if decision.failure?

        Success(DecisionContexts::ShadowedDecisionV1.new(source.to_h.merge(decision: decision.value!)))
      end

      def conflict(**context)
        source = context.fetch(:conflict)
        decisions = transform_many(source.decisions) do |decision|
          resolved_decision(**context.except(:conflict), decision:)
        end
        return decisions if decisions.failure?

        Success(DecisionContexts::ConflictV1.new(source.to_h.merge(decisions: decisions.value!)))
      end

      def resolve_head(**context)
        @head_reference_resolver.call(**context)
      end

      def resolve_entity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_id:,
        target:
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

      def transform_many(values)
        transformed = []
        values.each do |value|
          result = yield(value)
          return result if result.failure?

          transformed << result.value!
        end
        Success(transformed.freeze)
      end

      def transform_optional(value)
        return Success(nil) unless value

        yield(value)
      end

      def locate(reference)
        @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "AgentChoice source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
