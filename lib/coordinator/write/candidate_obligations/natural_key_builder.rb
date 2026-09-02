# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class NaturalKeyBuilder
      def initialize(
        canonical_json: CanonicalJson.new,
        compound_marker_builder: CompoundMarkerBuilder.new(canonical_json:)
      )
        @canonical_json = canonical_json
        @compound_marker_builder = compound_marker_builder
      end

      def call(source:, target:, policy_partition_event:, policy_head:, rule_version:)
        document = IdentityDocumentV1.new(
          schema: IdentityDocumentV1::SCHEMA,
          rule_version:,
          source_surface: source.subject.surface_event,
          target_surface: target.subject.surface_event,
          policy_partition_event:,
          policy_head:
        )
        compound = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "candidate-compatibility-obligation",
            components: components(document)
          )
        )
        NaturalKeyV1.new(
          document:,
          digest: @canonical_json.sha256(document.to_h),
          marker: compound.marker
        )
      end

      private

      def components(document)
        [
          "source-surface-event:#{document.source_surface.event_id}",
          "target-surface-event:#{document.target_surface.event_id}",
          "policy-partition-event:#{document.policy_partition_event.event_id}",
          "policy-head-event:#{document.policy_head.event.event_id}",
          "rule-version:#{document.rule_version}"
        ]
      end
    end
  end
end
