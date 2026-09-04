# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class OutcomeStateLoader
      def initialize(
        event_store:,
        definition_loader: DefinitionLoader.new(event_store:),
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @definition_loader = definition_loader
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(obligation_id, through_revision: nil)
        loaded = @definition_loader.call(obligation_id)
        raise InvalidHistory, "Verification obligation does not exist" unless loaded

        events = @event_store.read(
          @stream_factory.verification_obligation(obligation_id),
          EventReadCriteria.new(
            event_types: EventQueries::VERIFICATION_OBLIGATION_OUTCOME.event_types,
            maximum_count: EventQueries::VERIFICATION_OBLIGATION_OUTCOME.maximum_count,
            direction: :asc,
            to_revision: through_revision
          )
        )
        evidence = events.filter_map do |event|
          next unless event.type == "VerificationEvidenceSubmitted"

          CompatibilityAssessments::EvidenceObservationV2.new(
            evidence: load_event(event),
            event: reference(event),
            assessment_input_digest: event.metadata.fetch("assessment_input_digest"),
            obligation_validity_input_digest: event.metadata.fetch("obligation_validity_input_digest"),
            policy: CandidateObligations::ImpactPolicyEvidenceV1.new(
              deep_symbolize(event.metadata.fetch("policy"))
            )
          )
        end
        selections = events.filter_map do |event|
          load_event(event).evidence_id if event.type == "VerificationObligationEvidenceSelected"
        end
        terminal_event = events.reverse.find do |event|
          %w[
            VerificationObligationSatisfied
            VerificationObligationFailed
            VerificationObligationWaived
            VerificationObligationInvalidated
          ].include?(event.type)
        end

        OutcomeStateV2.new(
          definition: loaded.definition,
          definition_event: loaded.reference,
          evidence:,
          selected_evidence_ids: selections,
          terminal_status: terminal_event && terminal_event.type.delete_prefix("VerificationObligation").downcase,
          terminal_event: terminal_event && reference(terminal_event),
          latest_revision: events.last&.stream_revision || loaded.event.stream_revision
        )
      end

      private

      def load_event(event)
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

      def deep_symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array then value.map { deep_symbolize(_1) }
        else value
        end
      end
    end
  end
end
