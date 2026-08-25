# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentArtifactContentGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:artifact_id).filled(:string)
      end

      rule(:artifact_id) do
        key.failure("must be a valid Artifact ID") unless Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(value)
      end
    end
  end
end
