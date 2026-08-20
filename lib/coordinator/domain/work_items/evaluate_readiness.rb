# frozen_string_literal: true

module Coordinator
  module Domain
    module WorkItems
      class EvaluateReadiness
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(change_set_state:, work_item_state:, command:, occurred_at:, decision_recorded:)
          denial = denied(change_set_state:, work_item_state:, command:, decision_recorded:)
          return denial if denial

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.work_item(command.work_item_id),
                  event: Events::WorkItemMadeReadyV1.new(
                    change_set_id: command.change_set_id,
                    work_item_id: command.work_item_id,
                    readiness_decision_id: command.readiness_decision_id,
                    reason: "change_set_activated",
                    made_ready_at: occurred_at
                  )
                )
              ]
            )
          )
        end

        private

        def denied(change_set_state:, work_item_state:, command:, decision_recorded:)
          return failure(:readiness_already_decided, "Readiness decision is already recorded", command) if decision_recorded

          unless change_set_state.status == "active"
            return failure(:change_set_not_active, "ChangeSet is not active", command)
          end

          unless change_set_state.work_item_ids.include?(command.work_item_id)
            return failure(:work_item_not_member, "WorkItem is not a ChangeSet member", command)
          end

          return failure(:work_item_not_found, "WorkItem does not exist", command) if work_item_state.absent?

          unless work_item_state.change_set_id == command.change_set_id
            return failure(:work_item_change_set_mismatch, "WorkItem belongs to another ChangeSet", command)
          end

          if %w[ready active].include?(work_item_state.status)
            return failure(:work_item_already_ready, "WorkItem is already ready or active", command)
          end

          unless work_item_state.status == "planned"
            return failure(:work_item_not_planned, "WorkItem cannot become ready from its current state", command)
          end

          incoming = change_set_state.dependencies.select do |dependency|
            dependency.consumer_work_item_id == command.work_item_id
          end
          return unless incoming.any?

          failure(
            :incoming_dependency_unsatisfied,
            "WorkItem has an incoming dependency without a satisfaction fact",
            command,
            dependency_ids: incoming.map(&:dependency_id)
          )
        end

        def failure(code, message, command, details = {})
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id,
                readiness_decision_id: command.readiness_decision_id
              }.merge(details)
            )
          )
        end
      end
    end
  end
end
