# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotVerificationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:history).value(Types.Instance(Domain::MergeSnapshotVerifications::HistoryV1))
        required(:command).value(Types.Instance(Commands::SubmitMergeSnapshotVerification))
        required(:snapshot_evidence).value(Types.Instance(MergeSnapshotVerifications::SnapshotEvidenceV1))
        required(:verification_id).filled(:string)
        required(:verification_input_digest).filled(:string)
      end

      rule(:plan, :history, :command, :snapshot_evidence, :verification_id, :verification_input_digest) do
        decision = Domain::MergeSnapshotVerifications::Submit.new.call(
          history: values[:history],
          command: values[:command],
          snapshot_evidence: values[:snapshot_evidence],
          verification_id: values[:verification_id],
          verification_input_digest: values[:verification_input_digest]
        )
        key(:plan).failure("must preserve the exact merge verification submission decision") unless
          decision.success? && decision.value! == values[:plan]
      end
    end
  end
end
