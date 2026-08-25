# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class SkillPublishBatch < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: %w[agent user])
          required(:id).filled(:string)
        end
        required(:batch_id).filled(:string)
        required(:items).array(:hash) do
          required(:command_id).filled(:string)
          required(:actor).hash do
            required(:kind).filled(:string, included_in?: %w[agent user])
            required(:id).filled(:string)
          end
          required(:name).filled(:string)
          required(:scope).filled(:string)
          required(:expected_revision).filled(:integer)
          required(:description).value(:string)
          required(:instructions).filled(:string)
          required(:assets).array(:hash) do
            required(:path).filled(:string)
            required(:media_type).filled(:string)
            required(:executable).value(:bool)
            required(:content_base64).value(:string)
          end
        end
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:batch_id) do
        key.failure("must be a UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:items) do
        if value.empty? || value.length > Types::OPERATION_BATCH_MAXIMUM_ITEMS
          key.failure("must contain 1..#{Types::OPERATION_BATCH_MAXIMUM_ITEMS} items")
          next
        end

        command_ids = value.map { _1.fetch(:command_id) }
        key.failure("must contain unique item command IDs") unless command_ids.uniq.length == command_ids.length

        item_contract = PublishSkillRevision.new
        value.each_with_index do |item, index|
          result = item_contract.call(item)
          key([ :items, index ]).failure(result.errors.to_h.inspect) if result.failure?
        end
      end

      rule(:command_id, :actor, :batch_id, :items) do
        encoded = CanonicalJson.new.encode(values.to_h)
        if encoded.bytesize > Types::OPERATION_BATCH_MAXIMUM_ENCODED_BYTES
          base.failure(
            "canonical batch input exceeds #{Types::OPERATION_BATCH_MAXIMUM_ENCODED_BYTES} bytes"
          )
        end
      rescue CanonicalJson::Error => error
        base.failure("canonical batch input is invalid: #{error.message}")
      end
    end
  end
end
