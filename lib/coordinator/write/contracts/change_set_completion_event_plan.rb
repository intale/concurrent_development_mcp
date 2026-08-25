# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class ChangeSetCompletionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::CompleteChangeSet))
        required(:work_items).array(Types.Instance(ChangeSetCompletions::WorkItemEvidenceV1))
        required(:release_state).maybe(Types.Instance(Domain::ReleaseSets::LifecycleStateV1))
        required(:completed_at).filled(:string)
      end

      rule(:plan, :command, :work_items, :release_state, :completed_at) do
        plan = values[:plan]
        command = values[:command]
        event = plan.writes.sole&.event if plan.writes.one?
        unless event.is_a?(Events::ChangeSetCompletedV1) &&
               plan.writes.sole.stream == StreamFactory.new.change_set(command.change_set_id)
          key(:plan).failure("must contain exactly one ChangeSet completion write")
          next
        end

        expected_release = values[:release_state]&.completion&.event
        unless event.change_set_id == command.change_set_id &&
               event.work_item_completions == values[:work_items] &&
               event.release_set_completion_event == expected_release &&
               event.rule_version == command.rule_version &&
               event.completed_at == values[:completed_at]
          key(:plan).failure("must preserve exact completion evidence, rule, and time")
        end
      end
    end
  end
end
