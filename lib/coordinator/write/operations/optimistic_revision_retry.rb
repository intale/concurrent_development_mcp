# frozen_string_literal: true

module Coordinator::Write::Operations
  class OptimisticRevisionRetry
    MAXIMUM_ATTEMPTS = 3

    def call
      attempts = 0
      begin
        attempts += 1
        yield
      rescue PgEventstore::WrongExpectedRevisionError
        retry if attempts < MAXIMUM_ATTEMPTS
        raise
      end
    end
  end
end
