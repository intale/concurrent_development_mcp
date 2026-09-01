# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class GovernanceBrowser
    class Catalog < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:decision_topic_id).maybe(:string)
        optional(:decision_policy_status).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::DECISION_POLICY_STATUSES
        )
        optional(:after_decision_id).maybe(:string)
        optional(:guidance_source).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::GUIDANCE_SOURCES
        )
        optional(:after_guidance_message_id).maybe(:string)
        optional(:choice_type).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::AGENT_CHOICE_TYPES
        )
        optional(:choice_status).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::AGENT_CHOICE_OBSERVATION_STATUSES
        )
        optional(:after_choice_id).maybe(:string)
        optional(:impact_outcome).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::AGENT_CHOICE_IMPACT_ASSESSMENT_OUTCOMES
        )
        optional(:after_impact_global_position).maybe(:integer, gteq?: 0)
        optional(:after_impact_assessment_id).maybe(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      %i[
        decision_topic_id
        after_decision_id
        after_guidance_message_id
        after_choice_id
        after_impact_assessment_id
      ].each do |name|
        rule(name) do
          next unless value

          key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
        end
      end

      rule(:after_impact_global_position, :after_impact_assessment_id) do
        position = values[:after_impact_global_position]
        identifier = values[:after_impact_assessment_id]
        base.failure("impact cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
      end
    end

    class Decision < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:decision_id).filled(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:decision_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Guidance < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:message_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_revision).filled(:integer, gteq?: -1)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:message_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Choice < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:repository_id).filled(:string)
        required(:choice_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_impact_global_position).maybe(:integer, gteq?: 0)
        optional(:after_impact_assessment_id).maybe(:string)
      end

      rule(:repository_id) do
        key.failure("must be a UUIDv7") unless Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:choice_id, :after_impact_assessment_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_impact_global_position, :after_impact_assessment_id) do
        position = values[:after_impact_global_position]
        identifier = values[:after_impact_assessment_id]
        base.failure("impact cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
      end
    end

    class Receipts < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:tool_name).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::COORDINATION_TOOL_NAMES
        )
        optional(:status).maybe(:string, included_in?: [ "ok" ])
        optional(:after_command_id).maybe(:string)
      end

      rule(:after_command_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Receipt < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
      end

      rule(:command_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
