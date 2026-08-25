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
            required(:kind).filled(:string, included_in?: Types::DEPENDENCY_REQUIRED_OUTPUT_KINDS)
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

      rule(:dependency_kind, :required_output) do
        dependency_kind = values[:dependency_kind]
        required_output = values[:required_output]
        output_kind = {
          "requires_artifact" => "artifact",
          "requires_contract" => "contract",
          "requires_composite_verification" => "verification_run"
        }.fetch(dependency_kind, nil)

        if output_kind && required_output.nil?
          key(:required_output).failure("is required for #{dependency_kind}")
        elsif output_kind && required_output[:kind] != output_kind
          key([ :required_output, :kind ]).failure("must be #{output_kind} for #{dependency_kind}")
        elsif !output_kind && required_output
          key(:required_output).failure("must be absent for #{dependency_kind}")
        end
      end

      private

      def valid_identifier?(value)
        value.is_a?(String) && Types::IDENTIFIER_PATTERN.match?(value)
      end
    end
  end
end
