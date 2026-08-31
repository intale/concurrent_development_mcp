# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class SkillAssetManifestType < BaseObject
    graphql_name "SkillAssetManifest"

    field :byte_size, Integer, null: false
    field :content_digest, String, null: false, method: :content_sha256
    field :executable, Boolean, null: false
    field :media_type, String, null: false
    field :path, String, null: false
  end
end
