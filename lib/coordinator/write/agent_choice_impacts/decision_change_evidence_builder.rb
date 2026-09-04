# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class DecisionChangeEvidenceBuilder
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        source_contract: Contracts::DecisionChangeSourceEvent.new,
        schema_registry: EventSchemaRegistry.new,
        partition_builder: Decisions::DecisionPartitionBuilder.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @source_contract = source_contract
        @schema_registry = schema_registry
        @partition_builder = partition_builder
        @canonical_json = canonical_json
      end

      def call(source_event)
        validation = @source_contract.call(event: source_event)
        return invalid_source("source_envelope_invalid", validation.errors.to_h) if validation.failure?

        persisted = reload(source_event)
        return invalid_source("source_event_not_found", {}) unless persisted && persisted.id == source_event.id

        payload = load(persisted)
        definition = definition_for(persisted, payload)
        return definition if definition.failure?

        Success(build_evidence(persisted, payload, definition.value!))
      end

      private

      def reload(event)
        @event_store.read_at(
          StreamReference.new(
            context: event.stream.context,
            stream_name: event.stream.stream_name,
            stream_id: event.stream.stream_id
          ),
          event.stream_revision
        )
      end

      def definition_for(event, payload)
        case payload
        when Events::DecisionActivatedV1
          recorded = read_reference(payload.recorded_event)
          return invalid_source("recorded_event_not_found", payload.recorded_event.to_h) unless recorded

          recorded_payload = load(recorded)
          return Success(recorded_payload.definition) if recorded_payload.is_a?(Events::DecisionRecordedV1)

          invalid_source("recorded_event_type_invalid", payload.recorded_event.to_h)
        when Events::DecisionDefinitionCorrectedV1
          Success(payload.definition)
        when Events::DecisionActivatedV2
          definition = definition_before(event)
          return invalid_source("recorded_event_not_found", {}) unless definition

          Success(definition)
        when Events::DecisionDefinitionCorrectedV2
          Success(normalize_definition(payload.definition))
        else
          invalid_source("lifecycle_event_type_invalid", {})
        end
      end

      def read_reference(reference)
        event = @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        return unless event && event.id == reference.event_id && event.type == reference.type

        event
      end

      def build_evidence(event, payload, definition)
        DecisionChangeEvidenceV1.new(
          source_event: reference(event),
          source_global_position: event.global_position,
          source_command_id: event.metadata.fetch("command_id"),
          source_actor: Commands::Actor.new(
            kind: event.metadata.fetch("actor_kind"),
            id: event.metadata.fetch("actor_id")
          ),
          decision_id: payload.decision_id,
          change_kind: change_kind(payload),
          definition_digest: definition.digest,
          retroactivity: definition.document.enforcement.retroactivity,
          affected_partitions: affected_partitions(event, payload, definition),
          changed_at: event.created_at.utc.iso8601(6)
        )
      end

      def affected_partitions(event, payload, definition)
        partitions =
          case payload
          when Events::DecisionActivatedV1 then payload.partitions
          when Events::DecisionDefinitionCorrectedV1 then payload.previous_partitions + payload.partitions
          when Events::DecisionActivatedV2 then @partition_builder.call(definition)
          when Events::DecisionDefinitionCorrectedV2
            previous = definition_before(event)
            return [] unless previous

            @partition_builder.call(previous) + @partition_builder.call(definition)
          end
        partitions.uniq(&:partition_id).sort_by { _1.partition_id.b }.freeze
      end

      def change_kind(payload)
        if payload.is_a?(Events::DecisionActivatedV1) || payload.is_a?(Events::DecisionActivatedV2)
          "activated"
        else
          "corrected"
        end
      end

      def definition_before(event)
        return if event.stream_revision.zero?

        stream = StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
        definition_event = @event_store.read(
          stream,
          EventReadCriteria.new(
            event_types: %w[DecisionRecorded DecisionDefinitionCorrected],
            maximum_count: 2_048,
            direction: :asc
          )
        ).select { _1.stream_revision < event.stream_revision }.max_by(&:stream_revision)
        return unless definition_event

        payload = load(definition_event)
        normalize_definition(payload.definition)
      end

      def normalize_definition(value)
        return value if value.is_a?(Decisions::DecisionDefinitionV1)

        Decisions::DecisionDefinitionV1.new(
          document: value,
          digest: @canonical_json.sha256(value.to_h)
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def invalid_source(reason, evidence)
        Failure(
          OutcomeError.new(
            code: :agent_choice_impact_source_invalid,
            message: "Decision change source cannot start an AgentChoice impact scan",
            details: { reason:, evidence: }
          )
        )
      end
    end
  end
end
