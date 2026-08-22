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
        expected_streams = [ values[:work_item_stream], values[:attempt_stream], values[:attempt_stream] ]
        expected_types = [
          Events::WorkItemAcquiredV1,
          Events::AttemptAuthorizedV1,
          Events::AttemptStartedV1
        ]

        unless plan.writes.length == 3 &&
               plan.writes.map(&:stream) == expected_streams &&
               plan.events.map(&:class) == expected_types
          key(:plan).failure("must contain the ordered acquisition writes to WorkItem and Attempt")
          next
        end

        acquired, authorized, started = plan.events
        identifiers = plan.events.map { [ _1.change_set_id, _1.work_item_id ] }
        unless identifiers.uniq == [ [ command.change_set_id, command.work_item_id ] ] &&
               acquired.attempt_id == command.attempt_id &&
               authorized.attempt_id == command.attempt_id &&
               started.attempt_id == command.attempt_id &&
               acquired.agent_id == command.actor.id &&
               authorized.agent_id == command.actor.id &&
               authorized.base_snapshots == command.base_snapshots
          key(:plan).failure("must preserve the accepted command identity and repository bases")
        end

        timestamps = [ acquired.acquired_at, authorized.authorized_at, started.started_at ]
        key(:plan).failure("must use one prepared timestamp") unless timestamps.uniq.one?

        invalid_format = authorized.base_snapshots.any? do |snapshot|
          expected_format = snapshot.commit_oid.length == 40 ? "sha1" : "sha256"
          snapshot.object_format != expected_format
        end
        key(:plan).failure("must derive each Git object format from its OID length") if invalid_format
      end
    end
  end
end
