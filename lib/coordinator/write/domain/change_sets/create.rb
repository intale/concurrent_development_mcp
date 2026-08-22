# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class Create
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, occurred_at:)
          return duplicate_failure(command.change_set_id) unless state.absent?

          stream = @stream_factory.change_set(command.change_set_id)

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream:,
                  event: Events::ChangeSetCreatedV1.new(
                    change_set_id: command.change_set_id,
                    goal: command.goal,
                    created_at: occurred_at
                  )
                ),
                EventWrite.new(
                  stream:,
                  event: Events::ChangeSetAcceptanceCriteriaDefinedV1.new(
                    change_set_id: command.change_set_id,
                    acceptance_criteria: command.acceptance_criteria,
                    defined_at: occurred_at
                  )
                )
              ]
            )
          )
        end

        private

        def duplicate_failure(change_set_id)
          Failure(
            OutcomeError.new(
              code: :change_set_already_exists,
              message: "ChangeSet already exists",
              details: { change_set_id: }
            )
          )
        end
      end
    end
  end
end
