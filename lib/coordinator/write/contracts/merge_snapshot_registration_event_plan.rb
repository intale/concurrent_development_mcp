# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotRegistrationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:command).value(Types.Instance(Commands::RegisterMergeSnapshot))
        required(:state).value(Types.Instance(Domain::MergeSnapshots::RegistrationState))
        required(:commit_identity).value(Types.Instance(MergeSnapshots::CommitIdentityV1))
      end

      rule(:plan, :command, :state, :commit_identity) do
        command = values[:command]
        state = values[:state]
        identity = values[:commit_identity]
        expected = Domain::MergeSnapshots::Register.new.call(
          state:,
          command:,
          commit_identity: identity
        )

        unless expected.success? && values[:plan] == expected.value!
          key(:plan).failure("must preserve the exact ordered snapshot and commit-registry facts")
        end
      end
    end
  end
end
