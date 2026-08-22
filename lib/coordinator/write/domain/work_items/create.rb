# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkItems
      class Create
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(change_set_state:, work_item_state:, command:, occurred_at:)
          denial = denied(change_set_state:, work_item_state:, command:)
          return denial if denial

          Success(build_plan(command:, occurred_at:))
        end

        private

        def denied(change_set_state:, work_item_state:, command:)
          return failure(:change_set_not_found, "ChangeSet does not exist", command) if change_set_state.absent?
          return failure(:change_set_not_draft, "ChangeSet no longer accepts planning", command) unless change_set_state.status == "draft"
          return failure(:work_item_already_exists, "WorkItem already exists", command) unless work_item_state.absent?

          if change_set_state.work_item_ids.length >= 100
            return failure(:work_item_limit_reached, "ChangeSet WorkItem limit reached", command)
          end

          nil
        end

        def failure(code, message, command)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id
              }
            )
          )
        end

        def build_plan(command:, occurred_at:)
          EventPlan.new(
            writes: [
              EventWrite.new(
                stream: @stream_factory.work_item(command.work_item_id),
                event: Events::WorkItemCreatedV1.new(
                  work_item_id: command.work_item_id,
                  change_set_id: command.change_set_id,
                  repository_id: command.repository_id,
                  goal: command.goal,
                  acceptance_criteria: command.acceptance_criteria,
                  competitive_mode: false,
                  created_at: occurred_at
                )
              ),
              EventWrite.new(
                stream: @stream_factory.change_set(command.change_set_id),
                event: Events::WorkItemAddedToChangeSetV1.new(
                  change_set_id: command.change_set_id,
                  work_item_id: command.work_item_id,
                  added_at: occurred_at
                )
              )
            ]
          )
        end
      end
    end
  end
end
