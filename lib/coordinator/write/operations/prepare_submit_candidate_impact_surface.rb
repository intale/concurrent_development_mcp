# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareSubmitCandidateImpactSurface < Dry::Operation
      def initialize(
        contract: Contracts::SubmitCandidateImpactSurface.new,
        surface_builder: Candidates::ImpactSurfaceBuilder.new
      )
        @contract = contract
        @surface_builder = surface_builder
      end

      def call(input)
        attributes = step validate(input)
        surface = step @surface_builder.call(attributes)
        actor = attributes.fetch(:actor)

        Commands::SubmitCandidateImpactSurface.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          candidate_id: attributes.fetch(:candidate_id),
          repository_id: attributes.fetch(:repository_id),
          head_commit_oid: attributes.fetch(:head_commit_oid),
          manifest_digest: attributes.fetch(:manifest_digest),
          build_context_digest: attributes[:build_context_digest],
          surface:
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "SubmitCandidateImpactSurface input is invalid",
            details: result.errors.to_h
          )
        )
      end
    end
  end
end
