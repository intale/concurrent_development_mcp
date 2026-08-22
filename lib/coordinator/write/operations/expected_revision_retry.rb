# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExpectedRevisionRetry
      include Dry::Monads[:result]

      MAX_ATTEMPTS = 3

      def initialize(maximum_attempts: MAX_ATTEMPTS)
        @maximum_attempts = maximum_attempts
      end

      def call(task_id:)
        attempts = 0

        begin
          attempts += 1
          yield
        rescue PgEventstore::WrongExpectedRevisionError
          retry if attempts < @maximum_attempts

          Failure(
            Tasks::LifecycleError.new(
              code: :concurrency_conflict,
              message: "Task changed concurrently; the request may succeed if retried",
              task_id:
            )
          )
        end
      end
    end
  end
end
