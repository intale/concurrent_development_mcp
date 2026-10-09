# frozen_string_literal: true

module Coordinator::Read
  module AgentChoiceImpacts
    class DecisionChangeLoader
      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        partition_builder: Coordinator::Write::Decisions::DecisionPartitionBuilder.new,
        canonical_json: Coordinator::Write::CanonicalJson.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @partition_builder = partition_builder
        @canonical_json = canonical_json
      end

      def call(reference)
        event = @event_store.read_at(
          Coordinator::Write::StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        unless event && event.id == reference.event_id && event.type == reference.type
          raise InvalidProjectionSource, "AgentChoice impact decision source is missing"
        end

        payload = load_event(event)
        definition = definition_for(event, payload)
        evidence = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2.new(
          source_event: reference,
          source_global_position: event.global_position,
          source_command_id: event.metadata.fetch("command_id"),
          source_actor: {
            kind: event.metadata.fetch("actor_kind"),
            id: event.metadata.fetch("actor_id")
          },
          decision_id: payload.decision_id,
          change_kind: change_kind(payload),
          definition_digest: definition.digest,
          retroactivity: definition.document.enforcement.retroactivity,
          affected_partitions: affected_partitions(event, payload, definition)
        )
        DecisionChangeSourceV1.new(
          evidence:,
          changed_at: event.created_at.utc.iso8601(6)
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def definition_for(event, payload)
        case payload
        when Coordinator::Write::Events::DecisionActivatedV2
          definition_before(event) || raise(InvalidProjectionSource, "Activated Decision has no definition")
        when Coordinator::Write::Events::DecisionDefinitionCorrectedV2
          normalize_definition(payload.definition)
        else
          raise InvalidProjectionSource, "AgentChoice impact decision source has an unsupported schema"
        end
      end

      def affected_partitions(event, payload, definition)
        partitions = if payload.is_a?(Coordinator::Write::Events::DecisionActivatedV2)
                       @partition_builder.call(definition)
        else
                       previous = definition_before(event)
                       raise InvalidProjectionSource, "Corrected Decision has no previous definition" unless previous

                       @partition_builder.call(previous) + @partition_builder.call(definition)
        end
        partitions.uniq(&:partition_id).sort_by { _1.partition_id.b }.freeze
      end

      def change_kind(payload)
        payload.is_a?(Coordinator::Write::Events::DecisionActivatedV2) ? "activated" : "corrected"
      end

      def definition_before(event)
        return if event.stream_revision.zero?

        stream = Coordinator::Write::StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
        physical = @event_store.read_latest(
          stream,
          Coordinator::Write::LatestEventReadCriteria.new(
            event_types: %w[DecisionRecorded DecisionDefinitionCorrected],
            from_revision: event.stream_revision - 1
          )
        )
        physical && normalize_definition(load_event(physical).definition)
      end

      def normalize_definition(document)
        Coordinator::Write::Decisions::DecisionDefinitionV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h)
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
