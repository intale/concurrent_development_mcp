# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRegisterMergeSnapshot < Dry::Operation
      POLICY_VERSION = "merge-snapshot-registration/v1"

      def initialize(contract: Contracts::RegisterMergeSnapshot.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Commands::RegisterMergeSnapshot.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          merge_snapshot_id: attributes.fetch(:merge_snapshot_id),
          repository_id: attributes.fetch(:repository_id),
          target_branch: attributes.fetch(:target_branch),
          object_format: object_format(attributes.fetch(:target_base_commit_oid)),
          target_base_commit_oid: attributes.fetch(:target_base_commit_oid),
          ordered_candidates: attributes.fetch(:ordered_candidates).map do |candidate|
            MergeSnapshots::RequestedCandidateV1.new(candidate)
          end,
          merge_commit_oid: attributes.fetch(:merge_commit_oid),
          producer: MergeSnapshots::ProducerV1.new(attributes.fetch(:producer)),
          run_id: attributes.fetch(:run_id),
          produced_at: attributes.fetch(:produced_at),
          policy_version: POLICY_VERSION
        )
      end

      private

      def object_format(oid)
        oid.length == 40 ? "sha1" : "sha256"
      end

      def invalid(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RegisterMergeSnapshot input is invalid",
            details:
          )
        )
      end
    end
  end
end
