# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class ExpectedRevisionGuard
      include Dry::Monads[:result]

      def call(scan_id:)
        yield
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :candidate_impact_scan_concurrency_conflict,
            message: "Candidate impact scan changed concurrently; processing may succeed if retried",
            details: { scan_id: }
          )
        )
      end
    end
  end
end
