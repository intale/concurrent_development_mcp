# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class RevisionBuilder
      include Dry::Monads[:result]

      def initialize(asset_builder: AssetBuilder.new, canonical_json: CanonicalJson.new)
        @asset_builder = asset_builder
        @canonical_json = canonical_json
      end

      def call(identity:, description:, instructions:, assets:)
        built_assets = []
        assets.each do |asset|
          result = @asset_builder.call(asset)
          return result if result.failure?

          built_assets << result.value!
        end
        built_assets = built_assets.sort_by { _1.path.b }.freeze
        document = RevisionDocumentV2.new(
          schema: RevisionDocumentV2::SCHEMA,
          name: identity.name,
          scope: identity.scope,
          description:,
          instructions:,
          assets: built_assets
        )

        Success(RevisionContentV2.new(
          description:,
          instructions:,
          assets: built_assets,
          content_digest: @canonical_json.sha256(document.to_h)
        ))
      end
    end
  end
end
