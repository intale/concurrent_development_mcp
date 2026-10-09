# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkItems
      class State < Value
        attribute :work_item_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :repository_id, Types::RepositoryId.optional
        attribute :goal, Types::Goal.optional
        attribute :acceptance_criteria, Types::WorkItemStateAcceptanceCriteria
        attribute :competitive_mode, Types::Strict::Bool.optional.default(nil)
        attribute :status, Types::String.enum("absent", "planned", "ready", "active", "completed")
        attribute :active_attempt_id, Types::Identifier.optional.default(nil)
        attribute :active_agent_id, Types::Identifier.optional.default(nil)
        attribute :selected_candidate_id, Types::Identifier.optional.default(nil)
        attribute :selected_candidate_event, EventReference.optional.default(nil)
        attribute :produced_outputs,
                  Types::Array.of(Types.Instance(WorkItemOutputV1))
                    .constrained(max_size: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT)
                    .default([].freeze)

        def self.initial
          new(
            work_item_id: nil,
            change_set_id: nil,
            repository_id: nil,
            goal: nil,
            acceptance_criteria: [],
            competitive_mode: nil,
            status: "absent",
            active_attempt_id: nil,
            active_agent_id: nil,
            selected_candidate_id: nil,
            selected_candidate_event: nil,
            produced_outputs: [],
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          status == "absent"
        end

        def apply(event)
          case event
          when Events::WorkItemCreatedV2
            rebuild(work_item_id: event.work_item_id, status: "planned")
          when Events::WorkItemAddedToChangeSetV2
            rebuild(change_set_id: event.change_set_id)
          when Events::WorkItemAssignedToRepositoryV1
            rebuild(repository_id: event.repository_id)
          when Events::WorkItemGoalDefinedV1
            rebuild(goal: event.goal)
          when Events::WorkItemAcceptanceCriteriaDefinedV1
            rebuild(acceptance_criteria: event.acceptance_criteria)
          when Events::WorkItemCompetitiveModeSelectedV1
            rebuild(competitive_mode: event.competitive_mode)
          when Events::WorkItemMadeReadyV2
            rebuild(status: "ready")
          when Events::WorkItemAcquiredV2
            rebuild(status: "active", active_attempt_id: event.attempt_id, active_agent_id: event.agent_id)
          when Events::WorkItemRequeuedV2
            rebuild(
              status: "ready",
              active_attempt_id: nil,
              active_agent_id: nil,
              selected_candidate_id: nil,
              selected_candidate_event: nil,
              produced_outputs: [],
            )
          when Events::WorkItemCandidateSelectedV2
            rebuild(selected_candidate_id: event.candidate_id, selected_candidate_event: event.candidate_event)
          when Events::WorkItemOutputRecordedV1
            output = WorkItemOutputV1.new(kind: event.output_kind, key: event.output_key)
            rebuild(produced_outputs: produced_outputs + [ output ])
          when Events::WorkItemCompletedV2
            rebuild(status: "completed")
          else
            self
          end
        end

        private

        def rebuild(**changes)
          self.class.new(attributes.merge(changes))
        end
      end
    end
  end
end
