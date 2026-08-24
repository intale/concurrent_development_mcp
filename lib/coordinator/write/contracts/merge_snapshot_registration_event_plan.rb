# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotRegistrationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::RegisterMergeSnapshot))
        required(:state).value(Types.Instance(Domain::MergeSnapshots::RegistrationState))
        required(:commit_identity).value(Types.Instance(MergeSnapshots::CommitIdentityV1))
        required(:snapshot_event).value(Types.Instance(EventReference))
        required(:registered_at).filled(:string)
      end

      rule(:plan, :command, :state, :commit_identity, :snapshot_event, :registered_at) do
        command = values[:command]
        state = values[:state]
        identity = values[:commit_identity]
        snapshot_event = values[:snapshot_event]
        registered_at = values[:registered_at]
        expected = Domain::MergeSnapshots::Register.new.call(
          state:,
          command:,
          commit_identity: identity,
          snapshot_event:,
          registered_at:
        )

        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact ordered snapshot and commit-registry facts")
        end
      end
    end
  end
end
