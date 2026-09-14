# frozen_string_literal: true

module Coordinator::Read::Web::Contracts
  class GovernanceBrowser
    class Decisions < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:topic_id).maybe(:string)
        optional(:policy_status).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::DECISION_POLICY_STATUSES
        )
        optional(:after_decision_id).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:sort).filled(:string, included_in?: %w[newest_first oldest_first])
      end

      rule(:after_decision_id, :after_updated_at) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_decision_id].nil? == values[:after_updated_at].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end

      %i[topic_id after_decision_id].each do |name|
        rule(name) do
          next unless value

          key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
        end
      end
    end

    class GuidanceList < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:source).maybe(:string, included_in?: Coordinator::Shared::Types::GUIDANCE_SOURCES)
        optional(:after_message_id).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:sort).filled(:string, included_in?: %w[newest_first oldest_first])
      end

      rule(:after_message_id, :after_updated_at) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_message_id].nil? == values[:after_updated_at].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end

      rule(:after_message_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Choices < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:choice_type).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::AGENT_CHOICE_TYPES
        )
        optional(:status).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::AGENT_CHOICE_OBSERVATION_STATUSES
        )
        optional(:after_choice_id).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:sort).filled(:string, included_in?: %w[newest_first oldest_first])
      end

      rule(:after_choice_id, :after_updated_at) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_choice_id].nil? == values[:after_updated_at].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end

      rule(:after_choice_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Impacts < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 50)
        optional(:outcome).maybe(
          :string,
          included_in?: Coordinator::Shared::Types::AGENT_CHOICE_IMPACT_ASSESSMENT_OUTCOMES
        )
        optional(:after_updated_at).maybe(:string)
        optional(:after_assessment_id).maybe(:string)
        optional(:sort).filled(:string, included_in?: %w[newest_first oldest_first])
      end

      rule(:after_assessment_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_updated_at, :after_assessment_id) do
        position = values[:after_updated_at]
        identifier = values[:after_assessment_id]
        base.failure("impact cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
        key(:after_updated_at).failure("must be an event timestamp") if position &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(position)
      end
    end

    class Decision < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:decision_id).filled(:string)
      end

      rule(:decision_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Guidance < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:message_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_revision).filled(:integer, gteq?: -1)
      end

      rule(:message_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Choice < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:choice_id).filled(:string)
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:after_impact_updated_at).maybe(:string)
        optional(:after_impact_assessment_id).maybe(:string)
      end

      rule(:choice_id, :after_impact_assessment_id) do
        next unless value

        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:after_impact_updated_at, :after_impact_assessment_id) do
        position = values[:after_impact_updated_at]
        identifier = values[:after_impact_assessment_id]
        base.failure("impact cursor coordinates must both be present or absent") unless position.nil? == identifier.nil?
        key(:after_impact_updated_at).failure("must be an event timestamp") if position &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(position)
      end
    end

    class Impact < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:project_ref).filled(:string)
        required(:assessment_id).filled(:string)
      end

      rule(:assessment_id) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end
    end

    class Receipts < Dry::Validation::Contract
      config.validate_keys = true

      params do
        optional(:first).filled(:integer, gteq?: 1, lteq?: 100)
        optional(:tool_name).maybe(:string)
        optional(:status).maybe(:string, included_in?: [ "ok" ])
        optional(:after_command_id).maybe(:string)
        optional(:after_updated_at).maybe(:string)
        optional(:sort).filled(:string, included_in?: %w[newest_first oldest_first])
      end

      rule(:after_command_id, :after_updated_at) do
        base.failure("cursor coordinates must both be present or absent") unless
          values[:after_command_id].nil? == values[:after_updated_at].nil?
        key(:after_updated_at).failure("must be an event timestamp") if values[:after_updated_at] &&
          !Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(values[:after_updated_at])
      end

      %i[tool_name after_command_id].each do |name|
        rule(name) do
          next unless value

          key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
        end
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

    class CommandCompletion < Dry::Validation::Contract
      ROOT_KEYS = %i[
        command_id
        tool_name
        canonical_input_digest
        status
        summary
        receipt
        data
        warnings
        next_actions
        emitted_events
        completed_at
      ].freeze
      NEXT_ACTION_KEYS = %i[tool arguments].freeze
      EMITTED_EVENT_KEYS = %i[
        event_id
        type
        stream_context
        stream_name
        stream_id
        stream_revision
      ].freeze

      # `data` and `next_actions[].arguments` are intentionally open JSON
      # objects. Dry Schema's global key validator recursively rejects their
      # domain-specific keys, so this contract enforces the closed envelope
      # explicitly while leaving only those two payloads open.
      config.validate_keys = false

      json do
        required(:command_id).filled(:string)
        required(:tool_name).filled(:string)
        required(:canonical_input_digest).filled(:string)
        required(:status).filled(:string, eql?: "ok")
        required(:summary).filled(:string)
        required(:receipt).filled(:string)
        required(:data).value(:hash)
        required(:warnings).array(:string)
        required(:next_actions).array(:hash) do
          required(:tool).filled(:string)
          required(:arguments).value(:hash)
        end
        required(:emitted_events).array(:hash) do
          required(:event_id).filled(:string)
          required(:type).filled(:string)
          required(:stream_context).filled(:string)
          required(:stream_name).filled(:string)
          required(:stream_id).filled(:string)
          required(:stream_revision).filled(:integer, gteq?: 0)
        end
        required(:completed_at).filled(:string)
      end

      rule(:command_id, :tool_name, :receipt) do
        key.failure("must be an identifier") unless Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule do
        unexpected = values.to_h.keys - ROOT_KEYS
        base.failure("contains unknown keys: #{unexpected.sort.join(', ')}") if unexpected.any?
      end

      rule(:canonical_input_digest) do
        key.failure("must be a SHA-256 digest") unless Coordinator::Shared::Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:completed_at) do
        key.failure("must be a timestamp") unless Coordinator::Shared::Types::TIMESTAMP_PATTERN.match?(value)
      end

      rule(:warnings) do
        key.failure("must contain at most 100 warnings") if value.length > 100
      end

      rule(:next_actions) do
        key.failure("must contain at most 100 actions") if value.length > 100
        value.each_with_index do |action, index|
          unexpected = action.keys - NEXT_ACTION_KEYS
          key([ index ]).failure("contains unknown keys: #{unexpected.sort.join(', ')}") if unexpected.any?
          next if Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(action.fetch(:tool, ""))

          key([ index, :tool ]).failure("must be an identifier")
        end
      end

      rule(:emitted_events) do
        key.failure("must contain at most 100 events") if value.length > 100
        value.each_with_index do |event, index|
          unexpected = event.keys - EMITTED_EVENT_KEYS
          key([ index ]).failure("contains unknown keys: #{unexpected.sort.join(', ')}") if unexpected.any?
          valid = Coordinator::Shared::Types::UUID_V7_PATTERN.match?(event.fetch(:event_id, "")) &&
            %i[type stream_context stream_name stream_id].all? do |name|
              Coordinator::Shared::Types::IDENTIFIER_PATTERN.match?(event.fetch(name, ""))
            end
          key([ index ]).failure("contains an invalid event reference") unless valid
        end
      end
    end
  end
end
