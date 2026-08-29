# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class AssetBuilder
      include Dry::Monads[:result]

      def initialize(content_builder: Content::Builder.new)
        @content_builder = content_builder
      end

      def call(attributes)
        result = @content_builder.call(attributes.fetch(:content))
        return result if result.failure?

        content = result.value!
        if content.byte_size > Types::SKILL_ASSET_MAXIMUM_BYTES
          return Failure(
            OutcomeError.new(
              code: :content_invalid,
              message: "Skill asset content is invalid",
              details: { byte_size: content.byte_size, maximum: Types::SKILL_ASSET_MAXIMUM_BYTES }
            )
          )
        end

        Success(AssetV2.new(
          path: attributes.fetch(:path),
          executable: attributes.fetch(:executable),
          content:
        ))
      end
    end
  end
end
