# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCorrectDevelopmentArtifactClassification < Dry::Operation
      def initialize(contract: Contracts::CorrectDevelopmentArtifactClassification.new)
        @contract = contract
      end

      def call(input)
        attributes = step validate(input)
        actor = attributes.fetch(:actor)
        Commands::CorrectDevelopmentArtifactClassification.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          observation_id: attributes.fetch(:observation_id),
          expected_revision: attributes.fetch(:expected_revision),
          title: attributes.fetch(:title),
          kind: attributes.fetch(:kind),
          labels: attributes.fetch(:labels).uniq.sort_by(&:b),
          reason: attributes.fetch(:reason)
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "CorrectDevelopmentArtifactClassification input is invalid",
            details: result.errors.to_h
          )
        )
      end
    end
  end
end
