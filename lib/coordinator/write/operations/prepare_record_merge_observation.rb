# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRecordMergeObservation < Dry::Operation
      POLICY_VERSION = "merge-observation/v1"

      def initialize(contract: Contracts::RecordMergeObservation.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Commands::RecordMergeObservation.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          merge_snapshot_id: attributes.fetch(:merge_snapshot_id),
          authorization_event: EventReference.new(attributes.fetch(:authorization_event)),
          authorization_decision_digest: attributes.fetch(:authorization_decision_digest),
          repository_id: attributes.fetch(:repository_id),
          target_branch: attributes.fetch(:target_branch),
          object_format: attributes.fetch(:object_format),
          target_before_commit_oid: attributes.fetch(:target_before_commit_oid),
          target_after_commit_oid: attributes.fetch(:target_after_commit_oid),
          observer: MergeObservations::ObserverV1.new(attributes.fetch(:observer)),
          run_id: attributes.fetch(:run_id),
          observed_at: attributes.fetch(:observed_at),
          policy_version: POLICY_VERSION
        )
      end

      private

      def invalid(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RecordMergeObservation input is invalid",
            details:
          )
        )
      end
    end
  end
end
