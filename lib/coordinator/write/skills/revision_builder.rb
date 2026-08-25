# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class RevisionBuilder
      def initialize(asset_builder: AssetBuilder.new, canonical_json: CanonicalJson.new)
        @asset_builder = asset_builder
        @canonical_json = canonical_json
      end

      def call(identity:, description:, instructions:, assets:)
        built_assets = assets.map { @asset_builder.call(_1) }.sort_by { _1.path.b }.freeze
        document = RevisionDocumentV1.new(
          schema: RevisionDocumentV1::SCHEMA,
          skill_id: identity.skill_id,
          name: identity.name,
          scope: identity.scope,
          description:,
          instructions:,
          assets: built_assets
        )

        RevisionContentV1.new(
          description:,
          instructions:,
          assets: built_assets,
          content_digest: @canonical_json.sha256(document.to_h)
        )
      end
    end
  end
end
