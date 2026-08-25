# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareDeclareDevelopmentArtifactRelation < Dry::Operation
      def initialize(
        contract: Contracts::DeclareDevelopmentArtifactRelation.new,
        relation_builder: DevelopmentArtifacts::RelationBuilder.new
      )
        @contract = contract
        @relation_builder = relation_builder
      end

      def call(input)
        attributes = step validate(input)
        target_attributes = attributes.fetch(:target)
        target = DevelopmentArtifacts::RelationTargetV1.new(
          kind: target_attributes.fetch(:kind),
          id: target_attributes.fetch(:id)
        )
        relation_attributes = DevelopmentArtifacts::RelationAttributesV1.new(
          path: attributes.fetch(:attributes).fetch(:path, nil)
        )
        artifact_relation = @relation_builder.call(
          source_artifact_id: attributes.fetch(:source_artifact_id),
          relation: attributes.fetch(:relation),
          target:,
          attributes: relation_attributes
        )
        actor = attributes.fetch(:actor)

        Commands::DeclareDevelopmentArtifactRelation.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          artifact_relation:
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "DeclareDevelopmentArtifactRelation input is invalid",
            details: result.errors.to_h
          )
        )
      end
    end
  end
end
