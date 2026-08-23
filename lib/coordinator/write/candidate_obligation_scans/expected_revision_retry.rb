# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class ExpectedRevisionRetry
      include Dry::Monads[:result]

      MAX_ATTEMPTS = 3

      def initialize(maximum_attempts: MAX_ATTEMPTS)
        @maximum_attempts = maximum_attempts
      end

      def call(scan_id:)
        attempts = 0

        begin
          attempts += 1
          yield
        rescue PgEventstore::WrongExpectedRevisionError
          retry if attempts < @maximum_attempts

          Failure(
            OutcomeError.new(
              code: :candidate_impact_scan_concurrency_conflict,
              message: "Candidate impact scan changed concurrently; processing may succeed if retried",
              details: { scan_id:, attempts: }
            )
          )
        end
      end
    end
  end
end
