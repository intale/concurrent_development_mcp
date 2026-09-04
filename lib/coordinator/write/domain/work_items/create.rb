# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkItems
      class Create
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(change_set_state:, work_item_state:, repository_registration:, command:, occurred_at:)
          denial = denied(change_set_state:, work_item_state:, repository_registration:, command:)
          return denial if denial

          Success(build_plan(command:, occurred_at:))
        end

        private

        def denied(change_set_state:, work_item_state:, repository_registration:, command:)
          return failure(:change_set_not_found, "ChangeSet does not exist", command) if change_set_state.absent?
          return failure(:change_set_not_draft, "ChangeSet no longer accepts planning", command) unless change_set_state.status == "draft"
          return failure(:work_item_already_exists, "WorkItem already exists", command) unless work_item_state.absent?
          unless repository_registration&.repository_id == command.repository_id
            return Failure(
              OutcomeError.new(
                code: :repository_not_registered,
                message: "Repository is not registered",
                details: { repository_id: command.repository_id }
              )
            )
          end

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
          stream = @stream_factory.work_item(command.work_item_id)
          EventPlan.new(writes: [
            EventWrite.new(stream:, event: Events::WorkItemCreatedV2.new(work_item_id: command.work_item_id)),
            EventWrite.new(
              stream:,
              event: Events::WorkItemAddedToChangeSetV2.new(
                work_item_id: command.work_item_id,
                change_set_id: command.change_set_id
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::WorkItemAssignedToRepositoryV1.new(
                work_item_id: command.work_item_id,
                repository_id: command.repository_id
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::WorkItemGoalDefinedV1.new(
                work_item_id: command.work_item_id,
                goal: command.goal
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::WorkItemAcceptanceCriteriaDefinedV1.new(
                work_item_id: command.work_item_id,
                acceptance_criteria: command.acceptance_criteria
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::WorkItemCompetitiveModeSelectedV1.new(
                work_item_id: command.work_item_id,
                competitive_mode: false
              )
            )
          ])
        end
      end
    end
  end
end
