# frozen_string_literal: true

module Coordinator::Shared
  class CompoundMarkerBuilder
    def initialize(
      canonical_json: CanonicalJson.new,
      marker_codec: Markers::CodecV2.new
    )
      @canonical_json = canonical_json
      @marker_codec = marker_codec
    end

    def call(definition)
      components = definition.components.uniq.map { split_component(_1) }
      encoded = @marker_codec.call(purpose: definition.purpose, components:)
      unless encoded.success?
        raise ArgumentError, "compound marker is invalid: #{encoded.failure.errors.inspect}"
      end

      document = CompoundMarkerDocumentV1.new(
        schema: "coordinator-compound-marker/v1",
        purpose: definition.purpose,
        components: definition.components.uniq.sort_by(&:b)
      )

      CompoundMarker.new(
        purpose: document.purpose,
        components: document.components,
        digest: @canonical_json.sha256(document.to_h),
        marker: encoded.value!.marker
      )
    end

    private

    def split_component(component)
      dimension, separator, value = component.partition(":")
      raise ArgumentError, "compound marker component requires a dimension" if separator.empty?

      { dimension:, value: }
    end
  end
end
