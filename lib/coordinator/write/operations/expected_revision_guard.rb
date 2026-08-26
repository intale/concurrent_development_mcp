# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExpectedRevisionGuard
      include Dry::Monads[:result]

      def call(task_id:)
        yield
      rescue PgEventstore::WrongExpectedRevisionError
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
