# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class SourceBuilder
      def initialize(
        event_store:,
        exact_loader: Coordinator::Write::CandidateObligations::ExactEventLoader.new(event_store:),
        reference_builder: EventReferenceBuilder.new,
        contract: Contracts::CandidateObligationProcessSource.new
      )
        @exact_loader = exact_loader
        @reference_builder = reference_builder
        @contract = contract
      end

      def call(event)
        reference = @reference_builder.call(event)
        persisted = @exact_loader.call(reference)
        source = SourceV1.new(
          event: persisted.event,
          reference: persisted.reference,
          payload: persisted.payload
        )
        validation = @contract.call(source:)
        return source if validation.success?

        raise CandidateObligationProcessRejected,
              "Candidate-obligation process source is invalid: #{validation.errors.to_h.inspect}"
      rescue Coordinator::Write::CandidateObligations::InvalidHistory => error
        raise CandidateObligationProcessRejected, error.message
      end
    end
  end
end
