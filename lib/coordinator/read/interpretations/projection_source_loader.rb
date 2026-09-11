# frozen_string_literal: true

module Coordinator::Read
  module Interpretations
    class ProjectionSourceLoader
      def initialize(event_store:, schema_registry: Coordinator::Write::EventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(event, proposal)
        source_event = @event_store.read_global_marked(
          Coordinator::Write::EventQueries.guidance_message("message:#{proposal.source_message_id}")
        ).first
        raise InvalidProjectionSource, "Interpretation source guidance is missing" unless source_event

        source = load_event(source_event)
        source_span = build_source_span(source.text, proposal.source_span)
        InterpretationProjectionSourceV2.new(
          proposal:,
          source_event: event_reference(source_event),
          source_span:,
          classifier: Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
            symbolize(event.metadata.fetch("classifier"))
          ),
          scope_provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
            symbolize(event.metadata.fetch("scope_provenance"))
          ),
          ambiguities: proposal.ambiguities.map.with_index do |description, index|
            Coordinator::Write::Interpretations::InterpretationAmbiguityV1.new(
              field: "unspecified_#{index + 1}",
              code: "reported_ambiguity",
              description:,
              options: []
            )
          end,
          assessment: Coordinator::Write::Interpretations::InterpretationAssessmentV1.new(
            status: proposal.assessment,
            reasons: [],
            questions: []
          ),
          proposed_at: event.created_at.utc.iso8601(6)
        )
      rescue Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def build_source_span(source_text, selected_text)
        start_character = source_text.index(selected_text)
        raise InvalidProjectionSource, "Interpretation source span is not present in guidance" unless start_character

        Coordinator::Write::Interpretations::SourceSpanV1.new(
          start_character:,
          end_character: start_character + selected_text.length,
          text: selected_text
        )
      end

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
