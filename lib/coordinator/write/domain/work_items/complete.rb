# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkItems
      class Complete
        include Dry::Monads[:result]

        RULE_VERSION = "work-item-completion/v1"

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(
          change_set_state:,
          work_item_state:,
          attempt_state:,
          candidate:,
          candidate_event:,
          command:,
          completed_at:
        )
          denial = denied(
            change_set_state:,
            work_item_state:,
            attempt_state:,
            candidate:,
            command:,
            completed_at:
          )
          return denial if denial

          Success(build_plan(command:, candidate_event:, completed_at:))
        end

        private

        def denied(change_set_state:, work_item_state:, attempt_state:, candidate:, command:, completed_at:)
          unless change_set_state.status == "active" &&
                 change_set_state.work_item_ids.include?(command.work_item_id)
            return failure(:change_set_not_active, "ChangeSet is not active for this WorkItem", command)
          end

          work_item_denial = denied_work_item(work_item_state, command)
          return work_item_denial if work_item_denial

          attempt_denial = denied_attempt(attempt_state, command)
          return attempt_denial if attempt_denial

          candidate_denial = denied_candidate(candidate, work_item_state, command)
          return candidate_denial if candidate_denial

          denied_write_set(attempt_state, command, completed_at:)
        end

        def denied_work_item(state, command)
          return failure(:work_item_not_found, "WorkItem does not exist", command) if state.absent?
          unless state.change_set_id == command.change_set_id
            return failure(:work_item_scope_mismatch, "WorkItem belongs to another ChangeSet", command)
          end
          return failure(:work_item_already_completed, "WorkItem is already completed", command) if state.status == "completed"
          unless state.status == "active" && state.active_attempt_id == command.attempt_id
            return failure(:work_item_not_active, "WorkItem is not active under the requested Attempt", command)
          end
          return if state.active_agent_id == command.actor.id

          failure(:attempt_owner_mismatch, "WorkItem belongs to another agent attribution", command)
        end

        def denied_attempt(state, command)
          return failure(:attempt_not_found, "Attempt does not exist", command) if state.absent?
          return failure(:attempt_already_completed, "Attempt is already completed", command) if state.status == "completed"
          unless state.status == "active" &&
                 state.change_set_id == command.change_set_id &&
                 state.work_item_id == command.work_item_id &&
                 state.attempt_id == command.attempt_id
            return failure(:attempt_scope_mismatch, "Attempt is not active in the requested scope", command)
          end
          return if state.agent_id == command.actor.id

          failure(:attempt_owner_mismatch, "Attempt belongs to another agent attribution", command)
        end

        def denied_candidate(candidate, work_item_state, command)
          return failure(:candidate_not_found, "Candidate does not exist", command) unless candidate
          unless candidate.change_set_id == command.change_set_id &&
                 candidate.work_item_id == command.work_item_id &&
                 candidate.attempt_id == command.attempt_id &&
                 candidate.candidate_id == command.candidate_id &&
                 candidate.repository_id == work_item_state.repository_id
            return failure(:candidate_scope_mismatch, "Candidate does not belong to the active WorkItem and Attempt", command)
          end
          unless candidate.agent_id == command.actor.id
            return failure(:candidate_actor_mismatch, "Candidate belongs to another agent attribution", command)
          end
          return if candidate.checkpoint_kind == "final"

          failure(:candidate_not_final, "Only a final Candidate can complete a WorkItem", command)
        end

        def denied_write_set(state, command, completed_at:)
          unless state.lease_set_id && state.lease_expires_at
            return failure(:write_set_not_reserved, "Attempt does not have an authoritative write set", command)
          end
          return if state.lease_released_at || completed_at >= state.lease_expires_at

          failure(
            :write_set_still_active,
            "Release the Attempt write set or retry after its recorded expiry before completion",
            command,
            lease_set_id: state.lease_set_id,
            expires_at: state.lease_expires_at
          )
        end

        def build_plan(command:, candidate_event:, completed_at:)
          common = {
            change_set_id: command.change_set_id,
            work_item_id: command.work_item_id,
            attempt_id: command.attempt_id,
            candidate_id: command.candidate_id,
            candidate_event:
          }

          EventPlan.new(
            writes: [
              EventWrite.new(
                stream: @stream_factory.work_item(command.work_item_id),
                event: Events::WorkItemCandidateSelectedV1.new(
                  **common,
                  selected_at: completed_at
                )
              ),
              EventWrite.new(
                stream: @stream_factory.attempt(command.attempt_id),
                event: Events::AttemptCompletedV1.new(
                  **common,
                  completed_at:
                )
              ),
              EventWrite.new(
                stream: @stream_factory.work_item(command.work_item_id),
                event: Events::WorkItemCompletedV1.new(
                  **common,
                  produced_outputs: command.produced_outputs,
                  rule_version: RULE_VERSION,
                  completed_at:
                )
              )
            ]
          )
        end

        def failure(code, message, command, **extra)
          Failure(
            OutcomeError.new(
              code:,
              message:,
              details: {
                change_set_id: command.change_set_id,
                work_item_id: command.work_item_id,
                attempt_id: command.attempt_id,
                candidate_id: command.candidate_id
              }.merge(extra)
            )
          )
        end
      end
    end
  end
end
