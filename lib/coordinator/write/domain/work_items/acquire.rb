# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkItems
      class Acquire
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(change_set_state:, work_item_state:, attempt_state:, command:, occurred_at:)
          denial = denied(change_set_state:, work_item_state:, attempt_state:, command:)
          return denial if denial

          Success(build_plan(command:, occurred_at:))
        end

        private

        def denied(change_set_state:, work_item_state:, attempt_state:, command:)
          unless change_set_state.status == "active" && change_set_state.work_item_ids.include?(command.work_item_id)
            return failure(:change_set_not_active, "ChangeSet is not active for this WorkItem", command)
          end

          unless work_item_state.change_set_id == command.change_set_id
            return failure(:work_item_not_ready, "WorkItem is not ready in this ChangeSet", command)
          end

          if work_item_state.status == "active"
            return failure(:work_item_unavailable, "WorkItem already has an active Attempt", command)
          end

          unless work_item_state.status == "ready"
            return failure(:work_item_not_ready, "WorkItem is not ready", command)
          end

          unless attempt_state.absent?
            return failure(:attempt_already_exists, "Attempt already exists", command)
          end

          snapshot = command.base_snapshots.first
          unless command.base_snapshots.one? && snapshot.repository_id == work_item_state.repository_id
            return failure(:repository_base_mismatch, "Repository base does not match the WorkItem", command)
          end

          nil
        end

        def build_plan(command:, occurred_at:)
          attempt_stream = @stream_factory.attempt(command.attempt_id)
          EventPlan.new(writes: [
            EventWrite.new(
              stream: attempt_stream,
              event: Events::AttemptAuthorizedV2.new(attempt_id: command.attempt_id)
            ),
            EventWrite.new(
              stream: attempt_stream,
              event: Events::AttemptAssignedToWorkItemV1.new(
                attempt_id: command.attempt_id,
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id
              )
            ),
            EventWrite.new(
              stream: attempt_stream,
              event: Events::AttemptAssignedToAgentV1.new(
                attempt_id: command.attempt_id,
                agent_id: command.actor.id
              )
            ),
            *command.base_snapshots.map do |snapshot|
              EventWrite.new(
                stream: attempt_stream,
                event: Events::AttemptBaseSnapshotRecordedV1.new(
                  attempt_id: command.attempt_id,
                  repository_id: snapshot.repository_id,
                  object_format: snapshot.object_format,
                  commit_oid: snapshot.commit_oid
                )
              )
            end,
            EventWrite.new(
              stream: attempt_stream,
              event: Events::AttemptStartedV2.new(attempt_id: command.attempt_id)
            ),
            EventWrite.new(
              stream: @stream_factory.work_item(command.work_item_id),
              event: Events::WorkItemAcquiredV2.new(
                work_item_id: command.work_item_id,
                change_set_id: command.change_set_id,
                attempt_id: command.attempt_id,
                agent_id: command.actor.id
              )
            )
          ])
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
