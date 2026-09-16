# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionLifecycleV1Transformer
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        interpretation_context_resolver:,
        target_event_reference_resolver:,
        document_transformer:,
        schema_registry: LegacyEventSchemaRegistry.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @interpretation_context_resolver = interpretation_context_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @document_transformer = document_transformer
        @schema_registry = schema_registry
        @canonical_json = canonical_json
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        decision = resolve_decision(
          migration_id:,
          source_config_name:,
          source_event:,
          source_payload:
        )
        return decision if decision.failure?

        target_stream = decision.value!.target_stream
        decision_id = target_stream.stream_id
        case source_payload
        when Events::DecisionRecordedV1
          interpretation = resolve_interpretation(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
          return interpretation if interpretation.failure?

          transform_recorded(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            target_stream:,
            decision_id:,
            interpretation_id: interpretation.value!.interpretation_id,
            source_message_id: interpretation.value!.source_message_id
          )
        when LegacyEvents::DecisionActivatedV1
          recorded = load_recorded(source_event:, source_upper_position:, source: source_payload)
          return recorded if recorded.failure?

          interpretation = resolve_interpretation(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: recorded.value!
          )
          return interpretation if interpretation.failure?

          transform_activated(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            recorded: recorded.value!,
            target_stream:,
            decision_id:,
            interpretation_id: interpretation.value!.interpretation_id
          )
        when LegacyEvents::DecisionDefinitionCorrectedV1
          interpretation = resolve_interpretation(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload
          )
          return interpretation if interpretation.failure?

          transform_corrected(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            target_stream:,
            decision_id:,
            interpretation_id: interpretation.value!.interpretation_id,
            source_message_id: interpretation.value!.source_message_id
          )
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve_decision(
        migration_id:,
        source_config_name:,
        source_event:,
        source_payload:
      )
        unless source_payload.decision_id == source_event.stream.stream_id
          return Failure(inconsistent(source_event, "decision identity does not match its stream"))
        end

        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "HumanGuidance",
          target_stream_name: "Decision",
          identity_role: "decision"
        )
      end

      def resolve_interpretation(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:
      )
        context = @interpretation_context_resolver.from_reference(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_reference: source.proposal_event,
          interpretation_id: source.interpretation_id,
          source_message_id: source.source_message_id
        )
        return context if context.failure?

        unless source.source_event == context.value!.source_proposal.source_event
          return Failure(inconsistent(source_event, "Decision source message differs from its proposal"))
        end

        @interpretation_context_resolver.validate_acceptance(
          source_event:,
          source_upper_position:,
          context: context.value!,
          source_reference: source.acceptance_event
        )
      end

      def transform_recorded(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:,
        decision_id:,
        interpretation_id:,
        source_message_id:
      )
        definition = transformed_definition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_definition: source.definition
        )
        return definition if definition.failure?

        document = definition.value!
        markers = decision_markers(
          decision_id:,
          interpretation_id:,
          interpretation_role: "activation",
          document:
        )
        metadata = definition_metadata(
          source_event,
          source:,
          document:,
          source_message_id:
        )
        Success([
          fact(
            target_stream:,
            event: Events::DecisionRecordedV2.new(
              decision_id:,
              interpretation_id:,
              source_message_id:,
              definition: document
            ),
            markers:,
            step_name: "record-decision",
            metadata_extension: metadata
          ),
          fact(
            target_stream:,
            event: Events::DecisionDerivedFromInterpretationV1.new(
              decision_id:,
              interpretation_id:
            ),
            markers:,
            step_name: "derive-decision-from-interpretation",
            metadata_extension: actor_metadata(source_event)
          )
        ])
      end

      def transform_activated(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        recorded:,
        target_stream:,
        decision_id:,
        interpretation_id:
      )
        target_record = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.recorded_event,
          target_stream:,
          target_event_type: "DecisionRecorded",
          target_step_name: "record-decision"
        )
        return target_record if target_record.failure?

        definition = transformed_definition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_definition: recorded.definition
        )
        return definition if definition.failure?

        document = definition.value!
        Success([
          fact(
            target_stream:,
            event: Events::DecisionActivatedV2.new(
              decision_id:,
              interpretation_id:,
              rationale: source.rationale.summary
            ),
            markers: decision_markers(
              decision_id:,
              interpretation_id:,
              interpretation_role: "activation",
              document:
            ),
            step_name: "activate-decision",
            metadata_extension: actor_metadata(
              source_event,
              definition_digest: @canonical_json.sha256(document.to_h)
            )
          )
        ])
      end

      def transform_corrected(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        target_stream:,
        decision_id:,
        interpretation_id:,
        source_message_id:
      )
        definition = transformed_definition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_definition: source.definition
        )
        return definition if definition.failure?

        document = definition.value!
        Success([
          fact(
            target_stream:,
            event: Events::DecisionDefinitionCorrectedV2.new(
              decision_id:,
              interpretation_id:,
              source_message_id:,
              definition: document,
              rationale: source.rationale.summary
            ),
            markers: decision_markers(
              decision_id:,
              interpretation_id:,
              interpretation_role: "correction",
              document:
            ),
            step_name: "correct-decision-definition",
            metadata_extension: definition_metadata(
              source_event,
              source:,
              document:,
              source_message_id:
            )
          )
        ])
      end

      def transformed_definition(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_definition:
      )
        @document_transformer.definition(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          definition: source_definition
        )
      end

      def load_recorded(source_event:, source_upper_position:, source:)
        reference = source.recorded_event
        persisted = @event_store.read_at(stream_for(reference), reference.stream_revision)
        unless persisted && persisted.id == reference.event_id && persisted.type == "DecisionRecorded" &&
            persisted.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "recorded Decision reference is absent"))
        end

        payload = @schema_registry.load(
          type: persisted.type,
          schema_version: persisted.metadata.fetch("schema_version"),
          data: persisted.data
        )
        unless payload.is_a?(Events::DecisionRecordedV1) &&
            payload.decision_id == source.decision_id &&
            payload.interpretation_id == source.interpretation_id
          return Failure(inconsistent(source_event, "recorded Decision reference is inconsistent"))
        end

        Success(payload)
      end

      def stream_for(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def decision_markers(decision_id:, interpretation_id:, interpretation_role:, document:)
        [
          "decision:#{decision_id}",
          "interpretation-#{interpretation_role}:#{interpretation_id}",
          "topic:#{document.topic.topic_id}",
          "topic-root:#{document.topic_root}"
        ]
      end

      def fact(target_stream:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream:,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def definition_metadata(source_event, source:, document:, source_message_id:)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata["policy_version"],
          classifier: source.classifier,
          scope_provenance: Interpretations::DecisionScopeProvenanceV1.new(
            source.scope_provenance.to_h.merge(source_message_id:)
          ),
          definition_digest: @canonical_json.sha256(document.to_h)
        )
      end

      def actor_metadata(source_event, definition_digest: nil)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata["policy_version"],
          definition_digest:
        )
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Decision lifecycle source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
