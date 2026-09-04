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
        expected_types = command.release_set_id ?
          [ Events::ChangeSetReleaseSetLinkedV1, Events::ChangeSetCompletedV2 ] :
          [ Events::ChangeSetCompletedV2 ]
        expected_stream = StreamFactory.new.change_set(command.change_set_id)
        unless plan.events.map(&:class) == expected_types && plan.writes.all? { _1.stream == expected_stream }
          key(:plan).failure("must contain the optional release relation followed by ChangeSet completion")
          next
        end

        unless plan.events.all? { _1.change_set_id == command.change_set_id } &&
               (!command.release_set_id || plan.events.first.release_set_id == command.release_set_id)
          key(:plan).failure("must preserve the ChangeSet and optional ReleaseSet identities")
        end
      end
    end
  end
end
