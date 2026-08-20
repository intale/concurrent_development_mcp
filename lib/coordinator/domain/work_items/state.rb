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

        def self.initial
          new(
            work_item_id: nil,
            change_set_id: nil,
            repository_id: nil,
            goal: nil,
            acceptance_criteria: [],
            status: "absent"
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
              status: "planned"
            )
          when Events::WorkItemMadeReadyV1
            self.class.new(
              work_item_id:,
              change_set_id:,
              repository_id:,
              goal:,
              acceptance_criteria:,
              status: "ready"
            )
          else
            self
          end
        end
      end
    end
  end
end
