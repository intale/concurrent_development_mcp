# frozen_string_literal: true

module Coordinator::Read
  module Decisions
    class InterpretationEvidenceLoader
      EVENT_TYPES = %w[
        DecisionInterpretationProposed
        DecisionInterpretationAccepted
      ].freeze

      def initialize(
        event_store:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(interpretation_id)
        events = @event_store.read(
          @stream_factory.interpretation(interpretation_id),
          Coordinator::Write::EventReadCriteria.new(
            event_types: EVENT_TYPES,
            maximum_count: 2,
            direction: :asc
          )
        )
        proposal_event = events.find { _1.type == "DecisionInterpretationProposed" }
        acceptance_event = events.find { _1.type == "DecisionInterpretationAccepted" }
        unless proposal_event && acceptance_event
          raise InvalidProjectionSource, "Decision interpretation evidence is incomplete"
        end

        proposal = load_event(proposal_event)
        acceptance = load_event(acceptance_event)
        unless proposal.is_a?(Coordinator::Write::Events::DecisionInterpretationProposedV2) &&
               acceptance.is_a?(Coordinator::Write::Events::DecisionInterpretationAcceptedV2) &&
               proposal.interpretation_id == interpretation_id &&
               acceptance.interpretation_id == interpretation_id
          raise InvalidProjectionSource, "Decision interpretation evidence does not match its stream"
        end

        source_event = @event_store.read_global_marked(
          Coordinator::Write::EventQueries.guidance_message("message:#{proposal.source_message_id}")
        ).first
        raise InvalidProjectionSource, "Decision source guidance is missing" unless source_event

        DecisionInterpretationEvidenceV2.new(
          source_event: event_reference(source_event),
          proposal_event: event_reference(proposal_event),
          acceptance_event: event_reference(acceptance_event),
          classifier: Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
            symbolize(proposal_event.metadata.fetch("classifier"))
          ),
          scope_provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
            symbolize(proposal_event.metadata.fetch("scope_provenance"))
          )
        )
      rescue Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
