# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactContentType < BaseObject
    graphql_name "DevelopmentArtifactContent"

    field :base64, String, null: true
    field :byte_size, Integer, null: false
    field :content_digest, String, null: false, method: :content_sha256
    field :encoding, String, null: false
    field :media_type, String, null: false
    field :text, String, null: true

    def base64
      object.respond_to?(:base64) ? object.base64 : nil
    end

    def text
      object.respond_to?(:text) ? object.text : nil
    end
  end
end
