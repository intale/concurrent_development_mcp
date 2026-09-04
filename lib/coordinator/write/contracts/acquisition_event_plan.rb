# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AcquisitionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::AcquireWorkItem))
        required(:work_item_stream).value(Types.Instance(StreamReference))
        required(:attempt_stream).value(Types.Instance(StreamReference))
      end

      rule(:plan, :command, :work_item_stream, :attempt_stream) do
        plan = values[:plan]
        command = values[:command]
        expected_streams = [ values[:attempt_stream] ] * (4 + command.base_snapshots.length) +
                           [ values[:work_item_stream] ]
        expected_types = [
          Events::AttemptAuthorizedV2,
          Events::AttemptAssignedToWorkItemV1,
          Events::AttemptAssignedToAgentV1,
          *([ Events::AttemptBaseSnapshotRecordedV1 ] * command.base_snapshots.length),
          Events::AttemptStartedV2,
          Events::WorkItemAcquiredV2
        ]

        unless plan.writes.length == expected_streams.length &&
               plan.writes.map(&:stream) == expected_streams &&
               plan.events.map(&:class) == expected_types
          key(:plan).failure("must contain the ordered acquisition writes to WorkItem and Attempt")
          next
        end

        authorized, assigned_work_item, assigned_agent, *tail = plan.events
        snapshots = tail.take(command.base_snapshots.length)
        started, acquired = tail.drop(command.base_snapshots.length)
        unless plan.events.all? { _1.attempt_id == command.attempt_id } &&
               assigned_work_item.change_set_id == command.change_set_id &&
               assigned_work_item.work_item_id == command.work_item_id &&
               assigned_agent.agent_id == command.actor.id &&
               acquired.change_set_id == command.change_set_id &&
               acquired.work_item_id == command.work_item_id &&
               acquired.agent_id == command.actor.id &&
               snapshots.map { [ _1.repository_id, _1.object_format, _1.commit_oid ] } ==
                 command.base_snapshots.map { [ _1.repository_id, _1.object_format, _1.commit_oid ] }
          key(:plan).failure("must preserve the accepted command identity and repository bases")
        end

        invalid_format = snapshots.any? do |snapshot|
          expected_format = snapshot.commit_oid.length == 40 ? "sha1" : "sha256"
          snapshot.object_format != expected_format
        end
        key(:plan).failure("must derive each Git object format from its OID length") if invalid_format
      end
    end
  end
end
