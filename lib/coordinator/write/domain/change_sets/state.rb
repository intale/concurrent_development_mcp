# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ChangeSets
      class State < Value
        attribute :change_set_id, Types::Identifier.optional
        attribute :goal, Types::Goal.optional
        attribute :status, Types::String.enum("absent", "draft", "active", "completed")
        attribute :acceptance_criteria, Types::StateAcceptanceCriteria
        attribute :work_item_ids, Types::WorkItemIds
        attribute :dependencies, Types::Array.of(Dependency).constrained(max_size: 500)
        attribute :dependency_satisfactions,
                  Types::Array.of(DependencySatisfaction)
                    .constrained(max_size: 500)
                    .default([].freeze)
        attribute :completed_at, Types::Timestamp.optional.default(nil)
        attribute :release_set_id, Types::UuidV7.optional.default(nil)

        def self.initial
          new(
            change_set_id: nil,
            goal: nil,
            status: "absent",
            acceptance_criteria: [],
            work_item_ids: [],
            dependencies: [],
            dependency_satisfactions: [],
            completed_at: nil,
            release_set_id: nil
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          status == "absent"
        end

        def dependency_satisfied?(dependency_id)
          dependency_satisfactions.any? { _1.dependency_id == dependency_id }
        end

        def apply(event)
          case event
          when Events::ChangeSetCreatedV1
            rebuild(change_set_id: event.change_set_id, goal: event.goal, status: "draft")
          when Events::ChangeSetCreatedV2
            rebuild(change_set_id: event.change_set_id, status: "draft")
          when Events::ChangeSetGoalDefinedV1
            rebuild(goal: event.goal)
          when Events::ChangeSetAcceptanceCriteriaDefinedV1,
               Events::ChangeSetAcceptanceCriteriaDefinedV2
            rebuild(acceptance_criteria: event.acceptance_criteria)
          when Events::WorkItemAddedToChangeSetV1,
               Events::WorkItemAddedToChangeSetV2
            rebuild(work_item_ids: (work_item_ids + [ event.work_item_id ]).uniq)
          when Events::WorkItemDependencyDeclaredV1,
               Events::WorkItemDependencyDeclaredV2
            rebuild(dependencies: dependencies + [ dependency_from(event) ])
          when Events::WorkItemDependencySatisfiedV1
            rebuild(dependency_satisfactions: dependency_satisfactions + [
              DependencySatisfaction.new(
                dependency_id: event.dependency_id,
                source_event: event.source_event,
                satisfied_at: event.satisfied_at
              )
            ])
          when Events::WorkItemDependencySatisfiedV2
            rebuild(dependency_satisfactions: dependency_satisfactions + [
              DependencySatisfaction.new(dependency_id: event.dependency_id, source_event: event.source)
            ])
          when Events::ChangeSetActivatedV1, Events::ChangeSetActivatedV2
            rebuild(status: "active")
          when Events::ChangeSetReleaseSetLinkedV1
            rebuild(release_set_id: event.release_set_id)
          when Events::ChangeSetCompletedV1
            rebuild(status: "completed", completed_at: event.completed_at)
          when Events::ChangeSetCompletedV2
            rebuild(status: "completed")
          else
            self
          end
        end

        private

        def rebuild(**changes)
          self.class.new(attributes.merge(changes))
        end

        def dependency_from(event)
          Dependency.new(
            dependency_id: event.dependency_id,
            producer_work_item_id: event.producer_work_item_id,
            consumer_work_item_id: event.consumer_work_item_id,
            dependency_kind: event.dependency_kind,
            required_output: event.required_output
          )
        end

      end
    end
  end
end
