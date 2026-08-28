# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareCaptureDevelopmentArtifact < Dry::Operation
      def initialize(
        contract: Contracts::CaptureDevelopmentArtifact.new,
        content_builder: DevelopmentArtifacts::ContentBuilder.new,
        artifact_builder: DevelopmentArtifacts::ArtifactBuilder.new,
        observation_builder: DevelopmentArtifacts::ObservationBuilder.new
      )
        @contract = contract
        @content_builder = content_builder
        @artifact_builder = artifact_builder
        @observation_builder = observation_builder
      end

      def call(input)
        attributes = step validate(input)
        source_attributes = attributes.fetch(:source)
        source = DevelopmentArtifacts::SourceV1.new(
          kind: source_attributes.fetch(:kind),
          locator: source_attributes.fetch(:locator),
          revision: source_attributes.fetch(:revision),
          observed_at: source_attributes.fetch(:observed_at),
          collector: source_attributes.fetch(:collector)
        )
        content = @content_builder.call(attributes.fetch(:content))
        artifact = @artifact_builder.call(
          scope: attributes.fetch(:scope),
          title: attributes.fetch(:title),
          kind: attributes.fetch(:kind),
          labels: attributes.fetch(:labels),
          content:,
          source:
        )
        observation = @observation_builder.call(artifact:)
        actor = attributes.fetch(:actor)

        Commands::CaptureDevelopmentArtifact.new(
          command_id: attributes.fetch(:command_id),
          actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          artifact:,
          observation:
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "CaptureDevelopmentArtifact input is invalid",
            details: result.errors.to_h
          )
        )
      end
    end
  end
end
