# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class RegisterRepository < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:command_id).filled(:string)
        required(:actor).hash do
          required(:kind).filled(:string, included_in?: [ "agent" ])
          required(:id).filled(:string)
        end
        required(:repository_id).filled(:string)
        required(:scope).filled(:string)
        required(:repository_key).filled(:string)
        optional(:display_name).maybe(:string)
        required(:paths).array(:string)
        required(:remotes).array(:string)
      end

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        actor_id = value[:id]
        next unless actor_id.is_a?(String)

        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(actor_id)
      end

      rule(:repository_id) do
        key.failure("must be a caller-created UUIDv7") unless Types::UUID_V7_PATTERN.match?(value)
      end

      rule(:scope) do
        validate_identity_text(key, value, maximum_bytes: 500)
      end

      rule(:repository_key) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:display_name) do
        validate_identity_text(key, value, maximum_bytes: 255) if value
      end

      rule(:paths) do
        item_keys = value.each_index.map { key([ :paths, _1 ]) }
        validate_collection(key, item_keys, value, maximum_items: 20, maximum_bytes: 1_024)
      end

      rule(:remotes) do
        item_keys = value.each_index.map { key([ :remotes, _1 ]) }
        validate_collection(key, item_keys, value, maximum_items: 20, maximum_bytes: 2_048)
      end

      private

      def validate_collection(key_object, item_keys, values, maximum_items:, maximum_bytes:)
        key_object.failure("must contain at most #{maximum_items} entries") if values.length > maximum_items
        key_object.failure("must not contain duplicates") unless values.uniq.length == values.length
        values.each_with_index do |value, index|
          validate_identity_text(item_keys.fetch(index), value, maximum_bytes:)
        end
      end

      def validate_identity_text(key_object, value, maximum_bytes:)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        key_object.failure("must be at most #{maximum_bytes} bytes") if value.bytesize > maximum_bytes
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end
    end
  end
end
