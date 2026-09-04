# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteSatisfyVerificationObligation
      def initialize(
        event_store:,
        executor: VerificationObligationOutcomes::Executor.new(event_store:),
        decider: Domain::VerificationObligationOutcomes::Satisfy.new
      )
        @executor = executor
        @decider = decider
      end

      def call(command, caused_by: nil)
        @executor.call(command:, decider: @decider, caused_by:)
      end
    end
  end
end
