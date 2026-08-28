# frozen_string_literal: true

module Coordinator::Write
  module Content
    class Builder
      include Dry::Monads[:result]

      def initialize(contract: InputContract.new)
        @contract = contract
      end

      def call(input)
        validation = @contract.call(input)
        return Failure(invalid_content(validation.errors.to_h)) unless validation.success?

        attributes = validation.to_h
        attributes.fetch(:encoding) == "utf-8" ? build_text(attributes) : build_binary(attributes)
      end

      private

      def build_text(attributes)
        text = attributes.fetch(:text)
        bytes = text.b

        Success(
          TextV1.new(
            encoding: "utf-8",
            media_type: attributes.fetch(:media_type),
            text:,
            content_sha256: digest(bytes),
            byte_size: bytes.bytesize
          )
        )
      end

      def build_binary(attributes)
        base64 = attributes.fetch(:base64)
        bytes = base64.unpack1("m0")

        Success(
          BinaryV1.new(
            encoding: "binary",
            media_type: attributes.fetch(:media_type),
            base64:,
            content_sha256: digest(bytes),
            byte_size: bytes.bytesize
          )
        )
      end

      def digest(bytes)
        "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}"
      end

      def invalid_content(errors)
        OutcomeError.new(
          code: :content_invalid,
          message: "Content is invalid",
          details: { errors: }
        )
      end
    end
  end
end
