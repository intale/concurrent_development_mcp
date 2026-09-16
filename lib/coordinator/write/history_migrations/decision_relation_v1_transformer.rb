# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionRelationV1Transformer
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        document_transformer:,
        head_reference_resolver:,
        partition_identity_mapper:,
        partition_delta_resolver:,
        slot_marker_builder: DecisionSlotMarkerBuilder.new,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @document_transformer = document_transformer
        @head_reference_resolver = head_reference_resolver
        @partition_identity_mapper = partition_identity_mapper
        @partition_delta_resolver = partition_delta_resolver
        @slot_marker_builder = slot_marker_builder
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        case source_payload
        when LegacyEvents::DecisionSlotOpenedV1
          transform_slot_opened(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::DecisionSlotHeadChangedV1
          transform_slot_head(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        when Events::DecisionPartitionAdvancedV1
          transform_partition(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def transform_slot_opened(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        unless source.slot.slot_id == source_event.stream.stream_id
          return Failure(inconsistent(source_event, "slot identity does not match its stream"))
        end

        context = slot_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_slot: source.slot
        )
        return context if context.failure?

        head = resolve_head(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          head: source.opened_by
        )
        return head if head.failure?

        target_stream, document, compound_marker = context.value!
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: Events::DecisionSlotOpenedV2.new(
              slot_id: target_stream.stream_id,
              slot: document,
              opened_by: head.value!.decision_id
            ),
            markers: slot_markers(compound_marker, document, head.value!.decision_id),
            step_name: "open-decision-slot",
            metadata_extension: actor_metadata(source_event, marker_codec_version: "v2")
          )
        ])
      end

      def transform_slot_head(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        unless source.slot_id == source_event.stream.stream_id
          return Failure(inconsistent(source_event, "slot identity does not match its stream"))
        end

        opening = load_slot_opening(source_event:, source_upper_position:)
        return opening if opening.failure?

        context = slot_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_slot: opening.value!.slot
        )
        return context if context.failure?

        head = if source.head
          resolve_head(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            head: source.head
          )
        else
          Success(nil)
        end
        return head if head.failure?

        target_stream, document, compound_marker = context.value!
        markers = slot_markers(compound_marker, document, head.value!&.decision_id)
        Success([
          TransformedFactV1.new(
            target_stream:,
            event: Events::DecisionSlotHeadChangedV2.new(
              slot_id: target_stream.stream_id,
              head: head.value!
            ),
            markers:,
            step_name: "change-decision-slot-head",
            metadata_extension: actor_metadata(source_event)
          )
        ])
      end

      def transform_partition(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        unless source.partition.partition_id == source_event.stream.stream_id
          return Failure(inconsistent(source_event, "partition identity does not match its stream"))
        end

        partition = @partition_identity_mapper.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          partition: source.partition
        )
        return partition if partition.failure?

        head = resolve_head(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          head: source.decision
        )
        return head if head.failure?

        delta = @partition_delta_resolver.call(
          source_event:,
          source_upper_position:
        )
        return delta if delta.failure?

        target_partition = partition.value!
        target_stream = StreamReference.new(
          context: "HumanGuidance",
          stream_name: "DecisionPartition",
          stream_id: target_partition.partition_id
        )
        markers = [
          "decision-partition:#{target_partition.partition_id}",
          "topic-root:#{target_partition.topic_root}",
          "decision:#{head.value!.decision_id}"
        ]
        facts = []
        revision = delta.value!.first_target_revision
        if delta.value!.remove
          facts << partition_fact(
            target_stream:,
            event: Events::DecisionRemovedFromPartitionV1.new(
              partition_id: target_partition.partition_id,
              partition_revision: revision,
              decision_id: head.value!.decision_id
            ),
            markers:,
            step_name: "remove-decision-from-partition",
            source_event:
          )
          revision += 1
        end
        if delta.value!.add
          facts << partition_fact(
            target_stream:,
            event: Events::DecisionAddedToPartitionV1.new(
              partition_id: target_partition.partition_id,
              partition_revision: revision,
              decision_id: head.value!.decision_id
            ),
            markers:,
            step_name: "add-decision-to-partition",
            source_event:
          )
        end
        Success(facts.freeze)
      end

      def slot_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_slot:
      )
        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "HumanGuidance",
          target_stream_name: "DecisionSlot",
          identity_role: "decision-slot"
        )
        return allocation if allocation.failure?

        document = @document_transformer.slot_document(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          document: source_slot.document
        )
        return document if document.failure?

        compound_marker = @slot_marker_builder.call(document.value!)
        Success([ allocation.value!.target_stream, document.value!, compound_marker ])
      end

      def load_slot_opening(source_event:, source_upper_position:)
        persisted = @event_store.read_at(stream_for(source_event), 0)
        unless persisted && persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "slot opening is absent"))
        end

        payload = @schema_registry.load(
          type: persisted.type,
          schema_version: persisted.metadata.fetch("schema_version"),
          data: persisted.data
        )
        return Success(payload) if payload.is_a?(LegacyEvents::DecisionSlotOpenedV1)

        Failure(inconsistent(source_event, "slot stream does not begin with DecisionSlotOpened@1"))
      end

      def resolve_head(**arguments)
        @head_reference_resolver.call(**arguments)
      end

      def partition_fact(target_stream:, event:, markers:, step_name:, source_event:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension: actor_metadata(source_event)
        )
      end

      def slot_markers(compound_marker, document, decision_id)
        markers = compound_marker.components + [
          compound_marker.marker,
          "topic-root:#{document.topic_id.split('.', 2).first}"
        ]
        markers << "decision:#{decision_id}" if decision_id
        markers
      end

      def actor_metadata(source_event, marker_codec_version: nil)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version: source_event.metadata["policy_version"],
          marker_codec_version:
        )
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Decision relation source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
