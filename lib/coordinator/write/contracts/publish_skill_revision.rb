# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class PublishSkillRevision < Dry::Validation::Contract
      config.validate_keys = true

      params do
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

      rule(:command_id) do
        key.failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value)
      end

      rule(:actor) do
        key([ :actor, :id ]).failure("must be a valid identifier") unless Types::IDENTIFIER_PATTERN.match?(value.fetch(:id))
      end

      rule(:name) do
        validate_identity_text(key, value, maximum_bytes: Types::SKILL_NAME_MAXIMUM_BYTES)
      end

      rule(:scope) do
        validate_identity_text(key, value, maximum_bytes: Types::SKILL_SCOPE_MAXIMUM_BYTES)
      end

      rule(:expected_revision) do
        key.failure("must be zero or greater") if value.negative?
      end

      rule(:description) do
        validate_utf8_size(key, value, maximum_bytes: Types::SKILL_DESCRIPTION_MAXIMUM_BYTES)
      end

      rule(:instructions) do
        validate_utf8_size(key, value, maximum_bytes: Types::SKILL_INSTRUCTIONS_MAXIMUM_BYTES)
      end

      rule(:assets) do
        if value.length > Types::SKILL_ASSET_MAXIMUM_COUNT
          key.failure("must contain at most #{Types::SKILL_ASSET_MAXIMUM_COUNT} assets")
          next
        end

        paths = value.map { _1.fetch(:path) }
        key.failure("must not contain duplicate paths") unless paths.uniq.length == paths.length

        total_bytes = 0
        value.each_with_index do |asset, index|
          path_key = key([ :assets, index, :path ])
          media_key = key([ :assets, index, :media_type ])
          content_key = key([ :assets, index, :content_base64 ])
          path = asset.fetch(:path)
          media_type = asset.fetch(:media_type)
          content = asset.fetch(:content_base64)

          path_key.failure("must be a safe relative POSIX path") unless valid_asset_path?(path)
          unless media_type.ascii_only? && Types::SKILL_MEDIA_TYPE_PATTERN.match?(media_type)
            media_key.failure("must be a visible ASCII media type")
          end

          bytes = decode_base64(content)
          unless bytes
            content_key.failure("must be canonical unwrapped Base64")
            next
          end
          if bytes.bytesize > Types::SKILL_ASSET_MAXIMUM_BYTES
            content_key.failure("decoded asset exceeds #{Types::SKILL_ASSET_MAXIMUM_BYTES} bytes")
          end
          total_bytes += bytes.bytesize
        end

        if total_bytes > Types::SKILL_ASSETS_TOTAL_MAXIMUM_BYTES
          key.failure("decoded assets exceed #{Types::SKILL_ASSETS_TOTAL_MAXIMUM_BYTES} total bytes")
        end
      end

      private

      def validate_identity_text(key_object, value, maximum_bytes:)
        validate_utf8_size(key_object, value, maximum_bytes:)
        key_object.failure("must not have leading or trailing whitespace") unless value == value.strip
        key_object.failure("must not contain control characters") if /[\u0000-\u001f\u007f]/.match?(value)
      end

      def validate_utf8_size(key_object, value, maximum_bytes:)
        valid_utf8 = value.encoding == Encoding::UTF_8 && value.valid_encoding?
        key_object.failure("must be valid UTF-8") unless valid_utf8
        key_object.failure("must be at most #{maximum_bytes} bytes") if value.bytesize > maximum_bytes
      end

      def valid_asset_path?(value)
        return false unless value.encoding == Encoding::UTF_8 && value.valid_encoding?
        return false unless value.bytesize.between?(1, Types::SKILL_ASSET_PATH_MAXIMUM_BYTES)
        return false if value.start_with?("/") || value.include?("\\")
        return false if /[\u0000-\u001f\u007f]/.match?(value)

        value.split("/", -1).none? { _1.empty? || _1 == "." || _1 == ".." }
      end

      def decode_base64(value)
        bytes = value.unpack1("m0")
        bytes if [ bytes ].pack("m0") == value
      rescue ArgumentError
        nil
      end
    end
  end
end
