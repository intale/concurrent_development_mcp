# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Attempts
      class Abandon
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(attempt_state:, candidate_state:, work_item_state:, set_state:, member_states:, command:, abandoned_at:)
          denial = denied(attempt_state:, candidate_state:, work_item_state:, set_state:, command:)
          return denial if denial

          withdrawals = member_states.select { _1.active_at?(abandoned_at) }.map do |state|
            Events::ResourceWorkIntentionWithdrawnV1.new(
              intention_id: state.intention_id,
              resource_id: state.resource_id,
              fencing_token: state.fencing_token,
              reason: command.reason
            )
          end
          writes = withdrawals.map do |event|
            EventWrite.new(
              stream: @stream_factory.resource_work_intention(event.intention_id),
              event:
            )
          end
          writes << EventWrite.new(
            stream: @stream_factory.attempt(command.attempt_id),
            event: Events::AttemptAbandonedV3.new(
              attempt_id: command.attempt_id,
              reason: command.reason
            )
          )
          writes << EventWrite.new(
            stream: @stream_factory.work_item(command.work_item_id),
            event: Events::WorkItemRequeuedV2.new(
              work_item_id: command.work_item_id,
              change_set_id: command.change_set_id,
              attempt_id: command.attempt_id,
              agent_id: command.actor.id,
              reason: command.reason
            )
          )
          Success(EventPlan.new(writes:))
        end

        private

        def denied(attempt_state:, candidate_state:, work_item_state:, set_state:, command:)
          attempt_denial = attempt_denied(attempt_state:, candidate_state:, command:)
          return attempt_denial if attempt_denial

          work_item_denial = work_item_denied(work_item_state:, command:)
          return work_item_denial if work_item_denial

          return if set_state.absent?
          return if set_state.attempt_id == command.attempt_id &&
                    set_state.work_item_id == command.work_item_id &&
                    set_state.change_set_id == command.change_set_id

          failure(:attempt_scope_mismatch, "Work-intention set belongs to another scope", command)
        end

        def attempt_denied(attempt_state:, candidate_state:, command:)
          return failure(:attempt_not_found, "Attempt does not exist", command) if attempt_state.absent?
          unless attempt_state.status == "active"
            return failure(:attempt_not_active, "Attempt is not active and cannot be abandoned", command)
          end
          if candidate_state&.checkpoint_kind == "final"
            return failure(
              :attempt_not_active,
              "Attempt has a final Candidate and must be completed instead of abandoned",
              command
            )
          end
          unless attempt_state.attempt_id == command.attempt_id &&
                 attempt_state.change_set_id == command.change_set_id &&
                 attempt_state.work_item_id == command.work_item_id
            return failure(:attempt_scope_mismatch, "Attempt does not belong to the requested scope", command)
          end
          return if attempt_state.agent_id == command.actor.id

          failure(:attempt_owner_mismatch, "Attempt belongs to another agent attribution", command)
        end

        def work_item_denied(work_item_state:, command:)
          unless work_item_state.status == "active" &&
                 work_item_state.change_set_id == command.change_set_id &&
                 work_item_state.work_item_id == command.work_item_id &&
                 work_item_state.active_attempt_id == command.attempt_id
            return failure(
              :work_item_unavailable,
              "WorkItem is not active under the requested Attempt",
              command
            )
          end
          return if work_item_state.active_agent_id == command.actor.id

          failure(:attempt_owner_mismatch, "WorkItem belongs to another agent attribution", command)
        end

        def failure(code, message, command)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id,
                attempt_id: command.attempt_id
              }
            )
          )
        end
      end
    end
  end
end
