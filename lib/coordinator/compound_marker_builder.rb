# frozen_string_literal: true

module Coordinator
  class CompoundMarkerBuilder
    def initialize(canonical_json: CanonicalJson.new)
      @canonical_json = canonical_json
    end

    def call(definition)
      document = CompoundMarkerDocumentV1.new(
        schema: "coordinator-compound-marker/v1",
        purpose: definition.purpose,
        components: definition.components.uniq.sort_by(&:b)
      )
      digest = @canonical_json.sha256(document.to_h)

      CompoundMarker.new(
        purpose: document.purpose,
        components: document.components,
        digest:,
        marker: "compound:#{document.purpose}:v1:#{digest}"
      )
    end
  end
end
