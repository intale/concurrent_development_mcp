# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareSubmitCandidate < Dry::Operation
      def initialize(
        contract: Contracts::SubmitCandidate.new,
        evidence_builder: Candidates::SubmissionEvidenceBuilder.new
      )
        @contract = contract
        @evidence_builder = evidence_builder
      end

      def call(input)
        attributes = step validate(input)
        evidence = step @evidence_builder.call(attributes)

        build_command(attributes, evidence:)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "SubmitCandidate input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes, evidence:)
        actor = attributes.fetch(:actor)
        Commands::SubmitCandidate.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          candidate_id: attributes.fetch(:candidate_id),
          change_set_id: attributes.fetch(:change_set_id),
          work_item_id: attributes.fetch(:work_item_id),
          attempt_id: attributes.fetch(:attempt_id),
          repository_id: attributes.fetch(:repository_id),
          target_branch: attributes.fetch(:target_branch),
          object_format: evidence.object_format,
          base_commit_oid: attributes.fetch(:base_commit_oid),
          head_commit_oid: attributes.fetch(:head_commit_oid),
          checkpoint_kind: attributes.fetch(:checkpoint_kind),
          lease_set_id: attributes.fetch(:lease_set_id),
          leases: attributes.fetch(:leases).map do |lease|
            Candidates::LeaseObservationV1.new(
              resource_key_hash: lease.fetch(:resource_key_hash),
              lease_id: lease.fetch(:lease_id),
              fencing_token: lease.fetch(:fencing_token)
            )
          end.sort_by { _1.resource_key_hash.b },
          manifest: evidence.manifest,
          build_context: evidence.build_context,
          actual_resources: evidence.actual_resources
        )
      end
    end
  end
end
