# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class InterpretationContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        guidance_message_identity_resolver:,
        marked_event_locator:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @guidance_message_identity_resolver = guidance_message_identity_resolver
        @marked_event_locator = marked_event_locator
        @schema_registry = schema_registry
      end

      def from_proposal(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_proposal:
      )
        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_proposal_event: source_event,
          source_proposal:,
          interpretation_id: source_proposal.interpretation_id,
          source_message_id: source_proposal.source_message_id
        )
      end

      def from_reference(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:,
        interpretation_id:,
        source_message_id:
      )
        proposal_event = load_reference(
          source_event:,
          source_upper_position:,
          source_reference:
        )
        return proposal_event if proposal_event.failure?

        proposal = load_proposal(source_event, proposal_event.value!)
        return proposal if proposal.failure?

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_proposal_event: proposal_event.value!,
          source_proposal: proposal.value!,
          interpretation_id:,
          source_message_id:
        )
      end

      def from_identity(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        interpretation_id:,
        source_message_id:
      )
        proposal_event = @marked_event_locator.call(
          source_event:,
          source_upper_position:,
          stream_context: "HumanGuidance",
          stream_name: "Interpretation",
          event_type: "DecisionInterpretationProposed",
          marker: "interpretation:#{interpretation_id}"
        )
        return proposal_event if proposal_event.failure?

        proposal = load_proposal(source_event, proposal_event.value!)
        return proposal if proposal.failure?

        resolve(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_proposal_event: proposal_event.value!,
          source_proposal: proposal.value!,
          interpretation_id:,
          source_message_id:
        )
      end

      def validate_acceptance(source_event:, source_upper_position:, context:, source_reference:)
        persisted = load_reference(source_event:, source_upper_position:, source_reference:)
        return persisted if persisted.failure?

        payload = load_payload(persisted.value!)
        proposal_reference = reference_for(context.source_proposal_event)
        unless payload.is_a?(Events::DecisionInterpretationAcceptedV1) &&
            payload.interpretation_id == context.source_proposal.interpretation_id &&
            payload.source_message_id == context.source_proposal.source_message_id &&
            payload.proposal_event == proposal_reference
          return Failure(inconsistent(source_event, "interpretation acceptance is inconsistent"))
        end

        Success(context)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "interpretation acceptance is invalid: #{error.message}"))
      end

      private

      def resolve(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_proposal_event:,
        source_proposal:,
        interpretation_id:,
        source_message_id:
      )
        unless valid_proposal?(
          source_proposal_event,
          source_proposal,
          interpretation_id:,
          source_message_id:,
          source_upper_position:
        )
          return Failure(inconsistent(source_event, "interpretation proposal is inconsistent"))
        end

        guidance = @guidance_message_identity_resolver.call(
          source_event:,
          source_upper_position:,
          source_reference: source_proposal.source_event,
          source_message_id:
        )
        return guidance if guidance.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event: source_proposal_event,
          target_stream_context: "HumanGuidance",
          target_stream_name: "Interpretation",
          identity_role: "interpretation:#{source_proposal_event.id}"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        Success(
          InterpretationContextV1.new(
            source_proposal:,
            source_proposal_event:,
            target_stream:,
            interpretation_id: target_stream.stream_id,
            source_message_id: guidance.value!.target_message_id,
            source_text: guidance.value!.source_message.text
          )
        )
      end

      def valid_proposal?(event, proposal, interpretation_id:, source_message_id:, source_upper_position:)
        event.type == "DecisionInterpretationProposed" &&
          event.stream.context == "HumanGuidance" &&
          event.stream.stream_name == "Interpretation" &&
          event.global_position <= source_upper_position &&
          proposal.interpretation_id == interpretation_id &&
          proposal.source_message_id == source_message_id &&
          proposal.scope_provenance.source_message_id == source_message_id
      end

      def load_reference(source_event:, source_upper_position:, source_reference:)
        persisted = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        if persisted &&
            persisted.id == source_reference.event_id &&
            persisted.type == source_reference.type &&
            persisted.global_position <= source_upper_position
          return Success(persisted)
        end

        Failure(inconsistent(source_event, "interpretation event reference is absent"))
      end

      def load_proposal(source_event, event)
        payload = load_payload(event)
        return Success(payload) if payload.is_a?(Events::DecisionInterpretationProposedV1)

        Failure(inconsistent(source_event, "interpretation reference is not DecisionInterpretationProposed@1"))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "interpretation proposal is invalid: #{error.message}"))
      end

      def load_payload(event)
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

      def reference_for(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
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
