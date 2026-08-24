# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareReleaseSet < Dry::Operation
      POLICY_VERSION = "release-set-preparation/v1"

      def initialize(contract: Contracts::PrepareReleaseSet.new)
        @contract = contract
      end

      def call(input)
        result = @contract.call(input)
        return invalid(result.errors.to_h) if result.failure?

        attributes = result.to_h
        actor = attributes.fetch(:actor)
        Commands::PrepareReleaseSet.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          release_set_id: attributes.fetch(:release_set_id),
          ordered_members: attributes.fetch(:ordered_members).map { build_member(_1) },
          policy_version: POLICY_VERSION
        )
      end

      private

      def build_member(attributes)
        binding = attributes.fetch(:snapshot_binding)
        ReleaseSets::RequestedMemberV1.new(
          repository_id: attributes.fetch(:repository_id),
          target_branch: attributes.fetch(:target_branch),
          object_format: attributes.fetch(:object_format),
          merge_snapshot_id: attributes.fetch(:merge_snapshot_id),
          snapshot_binding: MergeAuthorizations::SnapshotBindingV1.new(
            registration_event: EventReference.new(binding.fetch(:registration_event)),
            snapshot_digest: binding.fetch(:snapshot_digest),
            verification_event: EventReference.new(binding.fetch(:verification_event)),
            verification_digest: binding.fetch(:verification_digest)
          ),
          authorization_event: EventReference.new(attributes.fetch(:authorization_event)),
          authorization_decision_digest: attributes.fetch(:authorization_decision_digest)
        )
      end

      def invalid(details)
        Failure(OutcomeError.new(code: :invalid_input, message: "PrepareReleaseSet input is invalid", details:))
      end
    end
  end
end
