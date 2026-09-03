# frozen_string_literal: true

module Coordinator::Read
  module Contracts
    class DevelopmentArtifactRelationList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:artifact_id).filled(:string)
        optional(:direction).maybe(:string, included_in?: %w[incoming outgoing both])
        optional(:relation).maybe(
          :string,
          included_in?: Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS
        )
        optional(:include_superseded).maybe(:bool)
        optional(:cursor).maybe(:hash) do
          required(:after_observed_sequence).filled(:integer, gteq?: 0)
          required(:through_observed_sequence).maybe(:integer, gteq?: 0)
          required(:after_declared_global_position).maybe(:integer, gteq?: 0)
          required(:after_relation_id).maybe(:string)
        end
        optional(:limit).maybe(
          :integer,
          gteq?: 1,
          lteq?: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
        )
      end

      rule(:artifact_id) do
        key.failure("must be a valid Artifact ID") unless ProjectedDevelopmentArtifactId.valid?(value)
      end

      rule(:cursor) do
        next unless value

        after_position = value[:after_declared_global_position]
        after_relation_id = value[:after_relation_id]
        unless after_position.nil? == after_relation_id.nil?
          key.failure("declaration position and relation ID must both be present or absent")
        end
        if after_relation_id && !ProjectedDevelopmentArtifactRelationId.valid?(after_relation_id)
          key([ :cursor, :after_relation_id ]).failure("must be a valid relation ID")
        end
        through = value[:through_observed_sequence]
        if through && through < value.fetch(:after_observed_sequence)
          key([ :cursor, :through_observed_sequence ]).failure("must not precede the observed lower bound")
        end
        if after_position && through.nil?
          key.failure("a declaration position requires a fixed observation window")
        end
      end
    end
  end
end
