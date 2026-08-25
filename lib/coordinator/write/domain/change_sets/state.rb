# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class State < Value
        attribute :change_set_id, Types::Identifier.optional
        attribute :goal, Types::Goal.optional
        attribute :status, Types::String.enum("absent", "draft", "active")
        attribute :acceptance_criteria, Types::StateAcceptanceCriteria
        attribute :work_item_ids, Types::WorkItemIds
        attribute :dependencies, Types::Array.of(Dependency).constrained(max_size: 500)
        attribute :dependency_satisfactions,
                  Types::Array.of(DependencySatisfaction)
                    .constrained(max_size: 500)
                    .default([].freeze)

        def self.initial
          new(
            change_set_id: nil,
            goal: nil,
            status: "absent",
            acceptance_criteria: [],
            work_item_ids: [],
            dependencies: [],
            dependency_satisfactions: []
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
          when Events::ChangeSetCreatedV1
            self.class.new(
              change_set_id: event.change_set_id,
              goal: event.goal,
              status: "draft",
              acceptance_criteria:,
              work_item_ids:,
              dependencies:,
              dependency_satisfactions:
            )
          when Events::ChangeSetAcceptanceCriteriaDefinedV1
            self.class.new(
              change_set_id:,
              goal:,
              status:,
              acceptance_criteria: event.acceptance_criteria,
              work_item_ids:,
              dependencies:,
              dependency_satisfactions:
            )
          when Events::WorkItemAddedToChangeSetV1
            self.class.new(
              change_set_id:,
              goal:,
              status:,
              acceptance_criteria:,
              work_item_ids: work_item_ids + [ event.work_item_id ],
              dependencies:,
              dependency_satisfactions:
            )
          when Events::WorkItemDependencyDeclaredV1
            self.class.new(
              change_set_id:,
              goal:,
              status:,
              acceptance_criteria:,
              work_item_ids:,
              dependencies: dependencies + [
                Dependency.new(
                  dependency_id: event.dependency_id,
                  producer_work_item_id: event.producer_work_item_id,
                  consumer_work_item_id: event.consumer_work_item_id,
                  dependency_kind: event.dependency_kind,
                  required_output: event.required_output
                )
              ],
              dependency_satisfactions:
            )
          when Events::WorkItemDependencySatisfiedV1
            self.class.new(
              change_set_id:,
              goal:,
              status:,
              acceptance_criteria:,
              work_item_ids:,
              dependencies:,
              dependency_satisfactions: dependency_satisfactions + [
                DependencySatisfaction.new(
                  dependency_id: event.dependency_id,
                  source_event: event.source_event,
                  satisfied_at: event.satisfied_at
                )
              ]
            )
          when Events::ChangeSetActivatedV1
            self.class.new(
              change_set_id:,
              goal:,
              status: "active",
              acceptance_criteria:,
              work_item_ids:,
              dependencies:,
              dependency_satisfactions:
            )
          else
            self
          end
        end

        def dependency_satisfied?(dependency_id)
          dependency_satisfactions.any? { _1.dependency_id == dependency_id }
        end
      end
    end
  end
end
