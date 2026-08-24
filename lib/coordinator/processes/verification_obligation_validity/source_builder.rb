# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class SourceBuilder
      def initialize(
        event_store:,
        exact_loader: Coordinator::Write::CandidateObligations::ExactEventLoader.new(event_store:),
        contract: Contracts::VerificationObligationValiditySource.new
      )
        @exact_loader = exact_loader
        @contract = contract
      end

      def call(event)
        persisted = @exact_loader.call(reference(event))
        source = SourceV1.new(
          event: persisted.event,
          reference: persisted.reference,
          payload: persisted.payload
        )
        result = @contract.call(source:)
        return source if result.success?

        raise VerificationObligationValidityProcessRejected,
              "Validity process source is invalid: #{result.errors.to_h.inspect}"
      rescue Coordinator::Write::CandidateObligations::InvalidHistory => error
        raise VerificationObligationValidityProcessRejected, error.message
      end

      private

      def reference(event)
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
