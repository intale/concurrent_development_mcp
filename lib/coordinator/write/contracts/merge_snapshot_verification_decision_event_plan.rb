# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotVerificationDecisionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).maybe(Types.Instance(Domain::EventPlan))
        required(:history).value(Types.Instance(Domain::MergeSnapshotVerifications::HistoryV1))
        required(:command).value(Types.Instance(Commands::VerifyMergeSnapshot))
      end

      rule(:plan, :history, :command) do
        decision = Domain::MergeSnapshotVerifications::Verify.new.call(
          history: values[:history],
          command: values[:command]
        )
        key(:plan).failure("must preserve the exact merge verification decision") unless
          decision.success? && decision.value! == values[:plan]
      end
    end
  end
end
