# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PreparePublishSkillRevision < Dry::Operation
      def initialize(
        contract: Contracts::PublishSkillRevision.new,
        identity_builder: Skills::IdentityBuilder.new,
        revision_builder: Skills::RevisionBuilder.new
      )
        @contract = contract
        @identity_builder = identity_builder
        @revision_builder = revision_builder
      end

      def call(input)
        attributes = step validate(input)
        identity = @identity_builder.call(name: attributes.fetch(:name), scope: attributes.fetch(:scope))
        content = @revision_builder.call(
          identity:,
          description: attributes.fetch(:description),
          instructions: attributes.fetch(:instructions),
          assets: attributes.fetch(:assets)
        )

        build_command(attributes, identity:, content:)
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "PublishSkillRevision input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_command(attributes, identity:, content:)
        actor = attributes.fetch(:actor)
        Commands::PublishSkillRevision.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          skill_id: identity.skill_id,
          name: identity.name,
          scope: identity.scope,
          expected_revision: attributes.fetch(:expected_revision),
          description: content.description,
          instructions: content.instructions,
          assets: content.assets,
          content_digest: content.content_digest
        )
      end
    end
  end
end
