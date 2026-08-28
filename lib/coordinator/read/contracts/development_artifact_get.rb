# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentArtifactGet < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:artifact_id).filled(:string)
        optional(:observation_id).maybe(:string)
      end

      rule(:artifact_id) do
        key.failure("must be a valid Artifact ID") unless Types::DEVELOPMENT_ARTIFACT_ID_PATTERN.match?(value)
      end

      rule(:observation_id) do
        next unless value

        unless Types::DEVELOPMENT_ARTIFACT_OBSERVATION_ID_PATTERN.match?(value)
          key.failure("must be a valid Artifact observation ID")
        end
      end
    end
  end
end
