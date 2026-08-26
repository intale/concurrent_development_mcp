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
        relation_input = attributes.fetch(:attributes)
        relation_attribute_values = { path: relation_input.fetch(:path, nil) }
        relation_attribute_values[:fragment] = relation_input[:fragment] if relation_input.key?(:fragment)
        if relation_input.key?(:normalized_locator)
          relation_attribute_values[:normalized_locator] = relation_input[:normalized_locator]
        end
        relation_attributes = DevelopmentArtifacts::RelationAttributesV1.new(**relation_attribute_values)
        artifact_relation = @relation_builder.call(
          source_artifact_id: attributes.fetch(:source_artifact_id),
          relation: attributes.fetch(:relation),
          target:,
          attributes: relation_attributes
        )
        actor = attributes.fetch(:actor)

        command_values = {
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          artifact_relation:
        }
        if (supersedes = attributes[:supersedes])
          command_values[:supersedes_relation_id] = supersedes.fetch(:relation_id)
          command_values[:supersession_reason] = supersedes.fetch(:reason)
        end

        Commands::DeclareDevelopmentArtifactRelation.new(**command_values)
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
