# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class SkillAssetContentType < BaseObject
    graphql_name "SkillAssetContent"

    field :base64, String, null: true
    field :byte_size, Integer, null: false
    field :content_digest, String, null: false, method: :content_sha256
    field :encoding, String, null: false
    field :executable, Boolean, null: false
    field :media_type, String, null: false
    field :path, String, null: false
    field :revision, Integer, null: false
    field :text, String, null: true

    def base64
      object.respond_to?(:base64) ? object.base64 : nil
    end

    def text
      object.respond_to?(:text) ? object.text : nil
    end
  end
end
