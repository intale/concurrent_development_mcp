# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DeclareWorkItemDependency < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: Types::ACTOR_KINDS)
          required(:id).filled(:string)
        end
        required(:change_set_id).filled(:string)
        required(:dependency_id).filled(:string)
        required(:producer_work_item_id).filled(:string)
        required(:consumer_work_item_id).filled(:string)
        required(:dependency_kind).filled(:string, included_in?: Types::DEPENDENCY_KINDS)
        required(:required_output).maybe do
          hash do
            required(:kind).filled(:string)
            required(:key).filled(:string)
          end
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:change_set_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:dependency_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:producer_work_item_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:consumer_work_item_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:required_output) do
        next if value.nil?

        value.each do |name, identifier|
          key([ :required_output, name ]).failure("must be a valid identifier") unless valid_identifier?(identifier)
        end
      end

      private

      def valid_identifier?(value)
        value.is_a?(String) && Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
