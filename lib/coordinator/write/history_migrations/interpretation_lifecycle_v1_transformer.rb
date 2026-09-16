# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class InterpretationLifecycleV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:, document_transformer:)
        @context_resolver = context_resolver
        @document_transformer = document_transformer
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        context = resolve_context(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return context if context.failure?

        unless same_source_stream?(source_event, context.value!.source_proposal_event)
          return Failure(inconsistent(source_event, "lifecycle event is outside its proposal stream"))
        end

        transform(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:,
          context: context.value!
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def resolve_context(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_payload:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          interpretation_id: source_payload.interpretation_id,
          source_message_id: source_payload.source_message_id
        }
        case source_payload
        when Events::DecisionInterpretationProposedV1
          @context_resolver.from_proposal(
            **common.except(:interpretation_id, :source_message_id),
            source_proposal: source_payload
          )
        when Events::DecisionInterpretationAcceptedV1, Events::DecisionInterpretationRejectedV1
          @context_resolver.from_reference(**common, source_reference: source_payload.proposal_event)
        when Events::DecisionClarificationRequiredV1
          @context_resolver.from_identity(**common)
        end
      end

      def transform(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_payload:,
        context:
      )
        common = {
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source: source_payload,
          context:
        }
        case source_payload
        when Events::DecisionInterpretationProposedV1
          transform_proposed(**common)
        when Events::DecisionClarificationRequiredV1
          transform_clarification(**common)
        when Events::DecisionInterpretationAcceptedV1
          transform_accepted(**common)
        when Events::DecisionInterpretationRejectedV1
          transform_rejected(**common)
        end
      end

      def transform_proposed(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        proposed_decision = @document_transformer.proposed_decision(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          proposed_decision: source.proposed_decision
        )
        return proposed_decision if proposed_decision.failure?

        Success([
          fact(
            context:,
            event: Events::DecisionInterpretationProposedV2.new(
              interpretation_id: context.interpretation_id,
              source_message_id: context.source_message_id,
              source_span: source.source_span&.text || context.source_text,
              proposed_decision: proposed_decision.value!,
              assessment: source.assessment.status,
              ambiguities: source.ambiguities.map(&:description)
            ),
            markers: proposal_markers(context),
            step_name: "propose-decision-interpretation",
            metadata_extension: proposal_metadata(source_event, source:, context:)
          )
        ])
      end

      def transform_clarification(**context)
        source = context.fetch(:source)
        interpretation = context.fetch(:context)
        Success([
          fact(
            context: interpretation,
            event: Events::DecisionClarificationRequiredV2.new(
              interpretation_id: interpretation.interpretation_id,
              source_message_id: interpretation.source_message_id,
              origin: source.origin,
              reasons: source.reasons,
              questions: source.questions.map(&:prompt),
              rationale: source.rationale&.summary || source.reasons.join(", ")
            ),
            markers: lifecycle_markers(interpretation),
            step_name: "require-decision-clarification",
            metadata_extension: actor_metadata(context.fetch(:source_event))
          )
        ])
      end

      def transform_accepted(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source:,
        context:
      )
        slot = @document_transformer.interpretation_slot(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          slot: source.slot,
          source_message_id: context.source_message_id
        )
        return slot if slot.failure?

        target_slot = slot.value!
        Success([
          fact(
            context:,
            event: Events::DecisionInterpretationAcceptedV2.new(
              interpretation_id: context.interpretation_id,
              source_message_id: context.source_message_id,
              slot: target_slot,
              rationale: source.rationale.summary
            ),
            markers: lifecycle_markers(context) +
              target_slot.compound_marker.components + [ target_slot.compound_marker.marker ],
            step_name: "accept-decision-interpretation",
            metadata_extension: actor_metadata(source_event)
          )
        ])
      end

      def transform_rejected(**context)
        source = context.fetch(:source)
        interpretation = context.fetch(:context)
        Success([
          fact(
            context: interpretation,
            event: Events::DecisionInterpretationRejectedV2.new(
              interpretation_id: interpretation.interpretation_id,
              source_message_id: interpretation.source_message_id,
              rationale: source.rationale.summary
            ),
            markers: lifecycle_markers(interpretation),
            step_name: "reject-decision-interpretation",
            metadata_extension: actor_metadata(context.fetch(:source_event))
          )
        ])
      end

      def fact(context:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream: context.target_stream,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def proposal_markers(context)
        [ "message:#{context.source_message_id}", "interpretation:#{context.interpretation_id}" ]
      end

      def lifecycle_markers(context)
        [ "message:#{context.source_message_id}", "interpretation-lifecycle:#{context.interpretation_id}" ]
      end

      def proposal_metadata(source_event, source:, context:)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata["policy_version"],
          classifier: source.classifier,
          scope_provenance: remapped_provenance(source.scope_provenance, context.source_message_id)
        )
      end

      def actor_metadata(source_event)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source_event.metadata["policy_version"]
        )
      end

      def remapped_provenance(provenance, source_message_id)
        Interpretations::DecisionScopeProvenanceV1.new(
          provenance.to_h.merge(source_message_id:)
        )
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
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
          message: "Interpretation lifecycle source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
