# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DependencySatisfactionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::SatisfyWorkItemDependency))
        required(:dependency).value(Types.Instance(Domain::ChangeSets::Dependency))
        required(:source).value(Types.Instance(DependencySatisfactions::SourceEvidenceV1))
        required(:satisfied_at).filled(:string)
      end

      rule(:plan, :command, :dependency, :source, :satisfied_at) do
        plan = values[:plan]
        command = values[:command]
        dependency = values[:dependency]
        source = values[:source]
        writes = plan.writes
        satisfaction = writes[0]&.event
        readiness = writes[1]&.event

        unless writes.length.between?(1, 2) && satisfaction.is_a?(Events::WorkItemDependencySatisfiedV2)
          key(:plan).failure("must contain satisfaction and optional readiness writes")
          next
        end
        unless writes[0].stream == StreamFactory.new.work_item(dependency.consumer_work_item_id)
          key(:plan).failure("must write satisfaction to the consumer WorkItem")
        end
        unless satisfaction.change_set_id == command.change_set_id &&
               satisfaction.dependency_id == dependency.dependency_id &&
               satisfaction.producer_work_item_id == dependency.producer_work_item_id &&
               satisfaction.consumer_work_item_id == dependency.consumer_work_item_id &&
               satisfaction.dependency_kind == dependency.dependency_kind &&
               satisfaction.required_output == dependency.required_output &&
               satisfaction.source == source.reference
          key(:plan).failure("satisfaction fact must match the command, declaration, source, and time")
        end
        next unless readiness

        unless readiness.is_a?(Events::WorkItemMadeReadyV2) &&
               writes[1].stream == StreamFactory.new.work_item(dependency.consumer_work_item_id) &&
               readiness.change_set_id == command.change_set_id &&
               readiness.work_item_id == dependency.consumer_work_item_id &&
               readiness.readiness_decision_id == command.command_id &&
               readiness.reason == "dependencies_satisfied"
          key(:plan).failure("readiness fact must match the final dependency decision")
        end
      end
    end
  end
end
