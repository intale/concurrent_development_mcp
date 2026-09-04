# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class ExpectedRevisionGuard
      include Dry::Monads[:result]

      def call(scan_id:)
        yield
      rescue PgEventstore::WrongExpectedRevisionError
        Failure(
          OutcomeError.new(
            code: :stale_stream,
            message: "Verification-obligation validity scan changed concurrently; the request may succeed if retried",
            details: { scan_id: }
          )
        )
      end
    end
  end
end
