# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareUpdateDevelopmentArtifact < Dry::Operation
      def initialize(
        contract: Contracts::UpdateDevelopmentArtifact.new,
        content_builder: DevelopmentArtifacts::ContentBuilder.new
      )
        @contract = contract
        @content_builder = content_builder
      end

      def call(input)
        attributes = step validate(input)
        actor = attributes.fetch(:actor)
        raw_changes = attributes.fetch(:changes)
        changes = {}
        changes[:scope] = raw_changes[:scope] if raw_changes.key?(:scope)
        changes[:title] = raw_changes[:title] if raw_changes.key?(:title)
        changes[:kind] = raw_changes[:kind] if raw_changes.key?(:kind)
        changes[:labels] = raw_changes[:labels].uniq.sort_by(&:b) if raw_changes.key?(:labels)
        changes[:content] = step @content_builder.call(raw_changes.fetch(:content)) if raw_changes.key?(:content)
        if raw_changes.key?(:source)
          source = raw_changes.fetch(:source)
          changes[:source] = DevelopmentArtifacts::SourceV1.new(
            kind: source.fetch(:kind), locator: source.fetch(:locator), revision: source.fetch(:revision),
            observed_at: source.fetch(:observed_at), collector: source.fetch(:collector)
          )
        end

        Commands::UpdateDevelopmentArtifact.new(
          command_id: attributes.fetch(:command_id), actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
          artifact_id: attributes.fetch(:artifact_id), expected_revision: attributes.fetch(:expected_revision),
          changes: DevelopmentArtifacts::UpdateChangesV1.new(changes)
        )
      end

      private

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(OutcomeError.new(code: :invalid_input, message: "UpdateDevelopmentArtifact input is invalid", details: result.errors.to_h))
      end
    end
  end
end
