# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class PreSemanticSkillRevision < Dry::Validation::Contract
      config.validate_keys = true

      params do
        required(:skill_id).filled(:string)
        required(:name).filled(:string)
        required(:scope).filled(:string)
        required(:revision).filled(:integer, gteq?: 1)
        required(:description).value(:string)
        required(:instructions).filled(:string)
        required(:assets).array(:hash) do
          required(:path).filled(:string)
          required(:media_type).filled(:string)
          required(:executable).value(:bool)
          required(:content_base64).value(:string)
          required(:content_sha256).filled(:string)
          required(:byte_size).filled(:integer, gteq?: 0)
        end
        required(:content_digest).filled(:string)
        required(:published_at).filled(:string)
      end

      rule(:skill_id) do
        key.failure("must be a valid Skill ID") unless Types::SKILL_ID_PATTERN.match?(value)
      end

      rule(:name) do
        validate_utf8_size(key, value, maximum_bytes: Types::SKILL_NAME_MAXIMUM_BYTES)
      end

      rule(:scope) do
        validate_utf8_size(key, value, maximum_bytes: Types::SKILL_SCOPE_MAXIMUM_BYTES)
      end

      rule(:description) do
        validate_utf8_size(key, value, maximum_bytes: Types::SKILL_DESCRIPTION_MAXIMUM_BYTES)
      end

      rule(:instructions) do
        validate_utf8_size(key, value, maximum_bytes: Types::SKILL_INSTRUCTIONS_MAXIMUM_BYTES)
      end

      rule(:content_digest) do
        key.failure("must be a SHA-256 digest") unless Types::SHA256_DIGEST_PATTERN.match?(value)
      end

      rule(:published_at) do
        key.failure("must be a canonical timestamp") unless Types::TIMESTAMP_PATTERN.match?(value)
      end

      rule(:assets) do
        if value.length > Types::SKILL_ASSET_MAXIMUM_COUNT
          key.failure("must contain at most #{Types::SKILL_ASSET_MAXIMUM_COUNT} assets")
          next
        end

        paths = value.map { _1.fetch(:path) }
        key.failure("must not contain duplicate paths") unless paths.uniq.length == paths.length

        value.each_with_index do |asset, index|
          validate_asset(key, asset, index)
        end
      end

      private

      def validate_asset(parent_key, asset, index)
        path = asset.fetch(:path)
        parent_key.failure("asset #{index} path is invalid") unless valid_asset_path?(path)

        media_type = asset.fetch(:media_type)
        unless media_type.ascii_only? && Types::SKILL_MEDIA_TYPE_PATTERN.match?(media_type)
          parent_key.failure("asset #{index} media type is invalid")
        end

        bytes = canonical_base64_bytes(asset.fetch(:content_base64))
        unless bytes
          parent_key.failure("asset #{index} Base64 is not canonical")
          return
        end

        parent_key.failure("asset #{index} exceeds the byte limit") if bytes.bytesize > Types::SKILL_ASSET_MAXIMUM_BYTES
        parent_key.failure("asset #{index} byte size does not match its bytes") unless bytes.bytesize == asset.fetch(:byte_size)

        digest = "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}"
        parent_key.failure("asset #{index} digest does not match its bytes") unless digest == asset.fetch(:content_sha256)
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

      def canonical_base64_bytes(value)
        bytes = value.unpack1("m0")
        bytes if [ bytes ].pack("m0") == value
      rescue ArgumentError
        nil
      end
    end
  end
end
