# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class WorkItemCompletionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::CompleteWorkItem))
        required(:candidate_event).value(Types.Instance(EventReference))
        required(:work_item_stream).value(Types.Instance(StreamReference))
        required(:attempt_stream).value(Types.Instance(StreamReference))
        required(:completed_at).filled(:string)
      end

      rule(:plan, :command, :candidate_event, :work_item_stream, :attempt_stream, :completed_at) do
        plan = values[:plan]
        command = values[:command]
        expected_streams = [ values[:work_item_stream], values[:attempt_stream], values[:work_item_stream] ]
        expected_types = [
          Events::WorkItemCandidateSelectedV1,
          Events::AttemptCompletedV1,
          Events::WorkItemCompletedV1
        ]
        unless plan.writes.length == 3 &&
               plan.writes.map(&:stream) == expected_streams &&
               plan.events.map(&:class) == expected_types
          key(:plan).failure("must contain the ordered Candidate selection and WorkItem/Attempt completion writes")
          next
        end

        selected, attempt, completed = plan.events
        unless plan.events.all? do |event|
          event.change_set_id == command.change_set_id &&
            event.work_item_id == command.work_item_id &&
            event.attempt_id == command.attempt_id &&
            event.candidate_id == command.candidate_id &&
            event.candidate_event == values[:candidate_event]
        end
          key(:plan).failure("must preserve the accepted command and Candidate identity")
        end
        unless selected.selected_at == values[:completed_at] &&
               attempt.completed_at == values[:completed_at] &&
               completed.completed_at == values[:completed_at]
          key(:plan).failure("must use one prepared timestamp")
        end
        unless completed.produced_outputs == command.produced_outputs &&
               completed.rule_version == Domain::WorkItems::Complete::RULE_VERSION
          key(:plan).failure("must preserve canonical outputs and the completion rule")
        end
      end
    end
  end
end
