# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class VerificationObligationValiditySource < Dry::Validation::Contract
      ALLOWED_TYPES = %w[
        DecisionPartitionAdvanced
        VerificationObligationCreated
        VerificationObligationValidityScanStarted
        VerificationObligationValidityScanProgressed
      ].freeze

      params do
        required(:source).value(Types.Instance(VerificationObligationValidity::SourceV1))
      end

      rule(:source) do
        source = value
        reference = source.reference
        failures = []
        failures << "event and reference must match" unless physical_reference(source.event) == reference
        failures << "event type must be supported" unless ALLOWED_TYPES.include?(reference.type)
        failures << "payload contract must match the physical type" unless source.payload.class.event_type == reference.type
        failures.each { key.failure(_1) }
      end

      private

      def physical_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
