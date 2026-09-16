# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceDecisionChangeTransformer
      include Dry::Monads[:result]

      PROCESS_RULE_VERSION = "history-migration-transformation/v1"
      TARGET_STEPS = {
        "DecisionActivated" => "activate-decision",
        "DecisionDefinitionCorrected" => "correct-decision-definition"
      }.freeze

      def initialize(
        event_store:,
        head_reference_resolver:,
        document_transformer:,
        partition_identity_mapper:,
        process_step_planner:,
        source_builder: AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:),
        schema_registry: LegacyEventSchemaRegistry.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @head_reference_resolver = head_reference_resolver
        @document_transformer = document_transformer
        @partition_identity_mapper = partition_identity_mapper
        @process_step_planner = process_step_planner
        @source_builder = source_builder
        @schema_registry = schema_registry
        @canonical_json = canonical_json
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        evidence:
      )
        decision_event = exact_event(evidence.source_event, source_upper_position:)
        return Failure(inconsistent(source_event, "decision change source is absent")) unless decision_event

        authoritative = @source_builder.call(decision_event)
        unless authoritative.success? && authoritative.value!.to_h == evidence.to_h.except(:changed_at)
          return Failure(inconsistent(source_event, "embedded decision change is not authoritative"))
        end

        source = authoritative.value!
        head = target_head(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          decision_change: source
        )
        return head if head.failure?

        definition = target_definition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          decision_event:
        )
        return definition if definition.failure?

        partitions = target_partitions(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          partitions: source.affected_partitions
        )
        return partitions if partitions.failure?

        process_step = target_process_step(migration_id:, decision_event:)
        target = head.value!
        Success(
          AgentChoiceImpacts::DecisionChangeEvidenceV2.new(
            source_event: target.event,
            source_global_position: source.source_global_position,
            source_command_id: process_step.target_command_id,
            source_actor: source.source_actor,
            decision_id: target.decision_id,
            change_kind: source.change_kind,
            definition_digest: @canonical_json.sha256(definition.value!.to_h),
            retroactivity: source.retroactivity,
            affected_partitions: partitions.value!
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def target_head(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        decision_change:
      )
        @head_reference_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          head: Decisions::DecisionHeadV1.new(
            decision_id: decision_change.decision_id,
            decision_revision: decision_change.source_event.stream_revision,
            event: decision_change.source_event
          )
        )
      end

      def target_definition(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        decision_event:
      )
        source_definition = source_definition(
          decision_event,
          source_event:,
          source_upper_position:
        )
        return source_definition if source_definition.failure?

        @document_transformer.definition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          definition: source_definition.value!
        )
      end

      def source_definition(decision_event, source_event:, source_upper_position:)
        payload = load(decision_event)
        case payload
        when LegacyEvents::DecisionActivatedV1
          recorded = exact_event(payload.recorded_event, source_upper_position:)
          recorded_payload = recorded && load(recorded)
          unless recorded_payload.is_a?(Events::DecisionRecordedV1) &&
              recorded_payload.decision_id == payload.decision_id &&
              recorded_payload.definition.digest == payload.definition_digest
            return Failure(inconsistent(source_event, "activated Decision definition is absent"))
          end

          Success(recorded_payload.definition)
        when LegacyEvents::DecisionDefinitionCorrectedV1
          Success(payload.definition)
        else
          Failure(inconsistent(source_event, "unsupported decision change source"))
        end
      end

      def target_partitions(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        partitions:
      )
        mapped = []
        partitions.each do |partition|
          result = @partition_identity_mapper.call(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            partition:
          )
          return result if result.failure?

          mapped << result.value!
        end
        Success(mapped.uniq(&:partition_id).sort_by { _1.partition_id.b }.freeze)
      end

      def target_process_step(migration_id:, decision_event:)
        step_name = TARGET_STEPS.fetch(decision_event.type)
        @process_step_planner.call(
          source_event: decision_event,
          process_name: "history-migration-#{migration_id}",
          step_name:,
          subject_kind: "source-event",
          subject_id: decision_event.id,
          rule_version: PROCESS_RULE_VERSION,
          allocate_target_entity: true
        )
      end

      def exact_event(reference, source_upper_position:)
        event = @event_store.read_at(stream_for(reference), reference.stream_revision)
        return unless event && event.id == reference.event_id && event.type == reference.type
        return unless event.global_position <= source_upper_position

        event
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "AgentChoice decision change is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
