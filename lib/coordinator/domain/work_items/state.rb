# frozen_string_literal: true

module Coordinator
  module Domain
    module WorkItems
      class State < Value
        attribute :work_item_id, Types::Identifier.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :repository_id, Types::RepositoryId.optional
        attribute :goal, Types::Goal.optional
        attribute :acceptance_criteria, Types::WorkItemStateAcceptanceCriteria
        attribute :status, Types::String.enum("absent", "planned", "ready", "active")
        attribute :active_attempt_id, Types::Identifier.optional.default(nil)
        attribute :active_agent_id, Types::Identifier.optional.default(nil)

        def self.initial
          new(
            work_item_id: nil,
            change_set_id: nil,
            repository_id: nil,
            goal: nil,
            acceptance_criteria: [],
            status: "absent",
            active_attempt_id: nil,
            active_agent_id: nil
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
          when Events::WorkItemCreatedV1
            self.class.new(
              work_item_id: event.work_item_id,
              change_set_id: event.change_set_id,
              repository_id: event.repository_id,
              goal: event.goal,
              acceptance_criteria: event.acceptance_criteria,
              status: "planned",
              active_attempt_id: nil,
              active_agent_id: nil
            )
          when Events::WorkItemMadeReadyV1
            self.class.new(
              work_item_id:,
              change_set_id:,
              repository_id:,
              goal:,
              acceptance_criteria:,
              status: "ready",
              active_attempt_id:,
              active_agent_id:
            )
          when Events::WorkItemAcquiredV1
            self.class.new(
              work_item_id:,
              change_set_id:,
              repository_id:,
              goal:,
              acceptance_criteria:,
              status: "active",
              active_attempt_id: event.attempt_id,
              active_agent_id: event.agent_id
            )
          else
            self
          end
        end
      end
    end
  end
end
