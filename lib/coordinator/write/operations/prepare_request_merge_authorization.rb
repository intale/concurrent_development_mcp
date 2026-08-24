# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRequestMergeAuthorization < Dry::Operation
      POLICY_VERSION = "merge-authorization/v1"

      def initialize(contract: Contracts::RequestMergeAuthorization.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        binding = attributes.fetch(:snapshot_binding)
        observation = attributes.fetch(:target_base_observation)
        expected_policy = attributes[:expected_impact_policy]
        Commands::RequestMergeAuthorization.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          merge_snapshot_id: attributes.fetch(:merge_snapshot_id),
          snapshot_binding: MergeAuthorizations::SnapshotBindingV1.new(
            registration_event: EventReference.new(binding.fetch(:registration_event)),
            snapshot_digest: binding.fetch(:snapshot_digest),
            verification_event: EventReference.new(binding.fetch(:verification_event)),
            verification_digest: binding.fetch(:verification_digest)
          ),
          target_base_observation: MergeAuthorizations::TargetBaseObservationV1.new(
            repository_id: observation.fetch(:repository_id),
            target_branch: observation.fetch(:target_branch),
            object_format: observation.fetch(:object_format),
            commit_oid: observation.fetch(:commit_oid),
            observer: MergeSnapshotVerifications::ProducerV1.new(observation.fetch(:observer)),
            run_id: observation.fetch(:run_id),
            observed_at: observation.fetch(:observed_at)
          ),
          expected_impact_policy: build_expected_policy(expected_policy),
          policy_version: POLICY_VERSION
        )
      end

      private

      def build_expected_policy(attributes)
        return unless attributes

        head = attributes.fetch(:head)
        MergeAuthorizations::ExpectedImpactPolicyV1.new(
          partition_event: EventReference.new(attributes.fetch(:partition_event)),
          head: Decisions::DecisionHeadV1.new(
            decision_id: head.fetch(:decision_id),
            decision_revision: head.fetch(:decision_revision),
            event: EventReference.new(head.fetch(:event))
          ),
          definition_digest: attributes.fetch(:definition_digest)
        )
      end

      def invalid(details)
        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RequestMergeAuthorization input is invalid",
            details:
          )
        )
      end
    end
  end
end
