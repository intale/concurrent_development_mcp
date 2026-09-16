# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceV1Transformer
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        target_event_reference_resolver:,
        document_transformer:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @target_event_reference_resolver = target_event_reference_resolver
        @document_transformer = document_transformer
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        target_stream = resolve_stream(
          migration_id:,
          source_config_name:,
          source_event:,
          source_payload:
        )
        return target_stream if target_stream.failure?

        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          target_stream: target_stream.value!.target_stream
        }
        case source_payload
        when Events::AgentChoiceRecordedV1
          transform_recorded(**common, source: source_payload)
        when Events::AgentChoiceAcceptedV1
          transform_accepted(**common, source: source_payload)
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve_stream(migration_id:, source_config_name:, source_event:, source_payload:)
        unless source_event.stream.context == "AgentGovernance" &&
            source_event.stream.stream_name == "AgentChoice" &&
            source_payload.choice_id == source_event.stream.stream_id
          return Failure(inconsistent(source_event, "choice identity does not match its stream"))
        end

        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "AgentGovernance",
          target_stream_name: "AgentChoice",
          identity_role: "agent-choice"
        )
      end

      def transform_recorded(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        documents = transform_documents(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source:
        )
        return documents if documents.failure?

        query_context, decision_context = documents.value!
        fact = TransformedFactV1.new(
          target_stream:,
          event: Events::AgentChoiceRecordedV2.new(
            choice_id: target_stream.stream_id,
            choice_type: source.choice_type,
            selected: source.selected,
            alternatives: source.alternatives,
            context: query_context,
            decision_context: DecisionContexts::EvidenceV2.new(document: decision_context.document),
            reason_summary: source.reason_summary
          ),
          markers: markers(
            choice_id: target_stream.stream_id,
            choice_type: source.choice_type,
            query_context:,
            decision_context:,
            assessment: nil
          ),
          step_name: "record-agent-choice",
          metadata_extension: actor_metadata(source_event)
        )
        Success([ fact ])
      end

      def transform_accepted(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:
      )
        recorded = load_recorded(
          source_event:,
          source_upper_position:,
          source:
        )
        return recorded if recorded.failure?

        source_recorded_event, source_recorded = recorded.value!
        target_recorded = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.recorded_event,
          target_stream:,
          target_event_type: "AgentChoiceRecorded",
          target_step_name: "record-agent-choice"
        )
        return target_recorded if target_recorded.failure?

        documents = transform_documents(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_recorded
        )
        return documents if documents.failure?

        assessment = @document_transformer.choice_assessment(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          assessment: source.assessment
        )
        return assessment if assessment.failure?

        query_context, decision_context = documents.value!
        unless source.context_digest == source_recorded.decision_context.digest
          return Failure(inconsistent(source_event, "acceptance context digest differs from its recorded choice"))
        end
        unless same_source_stream?(source_event, source_recorded_event) &&
            target_recorded.value!.stream_revision.zero?
          return Failure(inconsistent(source_event, "acceptance does not follow its recorded choice"))
        end

        fact = TransformedFactV1.new(
          target_stream:,
          event: Events::AgentChoiceAcceptedV2.new(
            choice_id: target_stream.stream_id,
            assessment: assessment.value!
          ),
          markers: markers(
            choice_id: target_stream.stream_id,
            choice_type: source_recorded.choice_type,
            query_context:,
            decision_context:,
            assessment: assessment.value!
          ),
          step_name: "accept-agent-choice",
          metadata_extension: actor_metadata(source_event, context_digest: decision_context.digest)
        )
        Success([ fact ])
      end

      def transform_documents(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        }
        query_context = @document_transformer.query_context(**common, context: source.context)
        return query_context if query_context.failure?

        decision_context = @document_transformer.decision_context(**common, context: source.decision_context)
        return decision_context if decision_context.failure?
        unless decision_context.value!.document.query_context == query_context.value!
          return Failure(inconsistent(source_event, "recorded query and Decision contexts differ"))
        end

        Success([ query_context.value!, decision_context.value! ])
      end

      def load_recorded(source_event:, source_upper_position:, source:)
        reference = source.recorded_event
        persisted = locate(reference)
        unless persisted && persisted.id == reference.event_id && persisted.type == "AgentChoiceRecorded" &&
            persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "recorded choice reference is absent"))
        end

        payload = @schema_registry.load(
          type: persisted.type,
          schema_version: persisted.metadata.fetch("schema_version"),
          data: persisted.data
        )
        unless payload.is_a?(Events::AgentChoiceRecordedV1) && payload.choice_id == source.choice_id
          return Failure(inconsistent(source_event, "recorded choice reference is inconsistent"))
        end

        Success([ persisted, payload ])
      end

      def markers(choice_id:, choice_type:, query_context:, decision_context:, assessment:)
        values = [
          "choice:#{choice_id}",
          "choice-type:#{choice_type}",
          "attempt:#{query_context.attempt_id}",
          "work-item:#{query_context.work_item_id}",
          "change-set:#{query_context.change_set_id}",
          "repository:#{query_context.repository_id}"
        ]
        values.concat(assessment.based_on_decisions.map { "decision:#{_1.decision_id}" }) if assessment
        values.concat(
          decision_context.document.partitions.map do |observation|
            "decision-partition:#{observation.partition.partition_id}"
          end
        )
        values.uniq.freeze
      end

      def actor_metadata(source_event, context_digest: nil)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: source_event.metadata["policy_version"],
          context_digest:
        )
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

      def same_source_stream?(left, right)
        left.stream.context == right.stream.context &&
          left.stream.stream_name == right.stream.stream_name &&
          left.stream.stream_id == right.stream.stream_id
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "AgentChoice lifecycle source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
