# frozen_string_literal: true

module Coordinator::Shared
  class ResourceMarkerCodec
    IDENTITY_PREFIX = "resource-identity:v1"
    CURRENT_PATH_PREFIX = "resource-current-path:v1"

    def identity(repository_id:, kind:, normalized_path:)
      [
        IDENTITY_PREFIX,
        "r=#{component(repository_id)}",
        "k=#{component(kind)}",
        "p=#{component(normalized_path)}"
      ].join("|")
    end

    def current_path(repository_id:, normalized_path:)
      [
        CURRENT_PATH_PREFIX,
        "r=#{component(repository_id)}",
        "p=#{component(normalized_path)}"
      ].join("|")
    end

    private

    def component(value)
      "#{value.bytesize}:#{value}"
    end
  end
end
