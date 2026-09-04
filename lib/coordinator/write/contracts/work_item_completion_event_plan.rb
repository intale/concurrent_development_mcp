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
        output_count = command.produced_outputs.length
        expected_streams = [ values[:work_item_stream] ] * (1 + output_count) +
                           [ values[:attempt_stream], values[:work_item_stream] ]
        expected_types = [
          Events::WorkItemCandidateSelectedV2,
          *([ Events::WorkItemOutputRecordedV1 ] * output_count),
          Events::AttemptCompletedV2,
          Events::WorkItemCompletedV2
        ]
        unless plan.writes.length == expected_streams.length &&
               plan.writes.map(&:stream) == expected_streams &&
               plan.events.map(&:class) == expected_types
          key(:plan).failure("must contain the ordered Candidate selection and WorkItem/Attempt completion writes")
          next
        end

        selected = plan.events.first
        outputs = plan.events.drop(1).take(output_count)
        attempt, completed = plan.events.last(2)
        unless selected.change_set_id == command.change_set_id &&
               selected.work_item_id == command.work_item_id &&
               selected.attempt_id == command.attempt_id &&
               selected.candidate_id == command.candidate_id &&
               selected.candidate_event == values[:candidate_event] &&
               outputs.map { [ _1.output_kind, _1.output_key ] } ==
                 command.produced_outputs.map { [ _1.kind, _1.key ] } &&
               outputs.all? { _1.work_item_id == command.work_item_id } &&
               attempt.attempt_id == command.attempt_id &&
               completed.work_item_id == command.work_item_id
          key(:plan).failure("must preserve the accepted command and Candidate identity")
        end
      end
    end
  end
end
