# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CoordinationTaskHistory < Dry::Validation::Contract
      params do
        required(:events).array(Types.Instance(Events::Base))
      end

      rule(:events) do
        events = value
        if events.length > 4
          key.failure("must contain at most four lifecycle facts")
          next
        end
        next if events.empty?

        unless events.first.is_a?(Events::CoordinationTaskSubmittedV2)
          key.failure("must start with CoordinationTaskSubmitted")
          next
        end

        task_ids = events.map(&:task_id).uniq
        key.failure("must describe one Task ID") unless task_ids.one?

        started = false
        cancellation_requested = false
        terminal = false

        events.drop(1).each do |event|
          valid = case event
          when Events::CoordinationTaskExecutionStartedV1
                    allowed = !started && !cancellation_requested && !terminal
                    started = true if allowed
                    allowed
          when Events::CoordinationTaskCancellationRequestedV1
                    allowed = started && !cancellation_requested && !terminal
                    cancellation_requested = true if allowed
                    allowed
          when Events::CoordinationTaskCompletedV2,
               Events::CoordinationTaskFailedV1
                    allowed = started && !terminal
                    terminal = true if allowed
                    allowed
          when Events::CoordinationTaskCancelledV1
                    allowed = !started && !terminal
                    terminal = true if allowed
                    allowed
          else
                    false
          end

          key.failure("contains an invalid lifecycle transition") unless valid
        end
      end
    end
  end
end
