# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ReleaseSets
      class CompleteActivated
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:)
          denial = denied(state:, command:)
          return denial if denial

          Success(completion_plan(command.release_set_id, "activated"))
        end

        private

        def completion_plan(release_set_id, outcome)
          stream = @stream_factory.release_set(release_set_id)
          EventPlan.new(
            writes: [
              EventWrite.new(
                stream:,
                event: Events::ReleaseSetOutcomeRecordedV1.new(release_set_id:, outcome:)
              ),
              EventWrite.new(
                stream:,
                event: Events::ReleaseSetCompletedV2.new(release_set_id:)
              )
            ]
          )
        end

        def denied(state:, command:)
          return failure(:release_set_not_found, "ReleaseSet has not been prepared") unless state.preparation
          return failure(:release_set_already_completed, "ReleaseSet is already completed") if state.completed?
          return failure(:release_set_not_activated, "ReleaseSet has not been activated") unless state.activation
          return failure(:release_activation_binding_stale, "Completion does not bind the exact activation") unless command.activation_event == state.activation.event

          nil
        end

        def failure(code, message)
          Failure(OutcomeError.new(code:, message:, details: {}))
        end
      end
    end
  end
end
