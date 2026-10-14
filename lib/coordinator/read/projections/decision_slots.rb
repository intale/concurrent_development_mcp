# frozen_string_literal: true

module Coordinator::Read::Projections
  class DecisionSlots
    def initialize(components: Coordinator::Shared::CanonicalMarkerComponentBuilder.new, canonical_json: Coordinator::Shared::CanonicalJson.new)
      @components, @canonical_json = components, canonical_json
    end

    def call(id, document)
      components = [ "topic:#{document.fetch(:topic_id)}", "conflict-dimension:#{document.fetch(:conflict_dimension)}",
        "resolution-strategy:#{document.fetch(:resolution_strategy)}" ] +
        @components.call(dimension: "scope", value: document.fetch(:exact_scope)) +
        @components.call(dimension: "conditions", value: document.fetch(:exact_conditions))
      components = components.uniq.sort_by(&:b)
      marker = Coordinator::Shared::Markers::CodecV2.encode(purpose: "decision-slot", components: components.map do |component|
        dimension, _, value = component.partition(":")
        { dimension:, value: }
      end)
      compound_marker = { purpose: "decision-slot", components:,
        digest: @canonical_json.sha256({ schema: "coordinator-compound-marker/v1", purpose: "decision-slot", components: }), marker: }
      { slot_id: id, document:, compound_marker: }
    end
  end
end
