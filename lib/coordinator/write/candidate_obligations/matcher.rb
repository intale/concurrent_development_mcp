# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class Matcher
      def call(source:, target:)
        reasons = []
        if source.subject.repository_id == target.subject.repository_id
          append_path_reason(reasons, source:, target:, kind: "changed_resource_overlap")
          append_path_reason(reasons, source:, target:, kind: "observed_input_changed")
        end
        append_semantic_reason(reasons, source:, target:)
        reasons.freeze
      end

      private

      def append_path_reason(reasons, source:, target:, kind:)
        target_paths = kind == "changed_resource_overlap" ? changed_paths(target) : observed_paths(target)
        matches = changed_paths(source).intersection(target_paths).sort_by(&:b)
        return if matches.empty?

        reasons << ImpactReasonV1.new(
          kind:,
          matches:,
          source_evidence: source.subject.manifest_event,
          target_evidence: kind == "changed_resource_overlap" ?
            target.subject.manifest_event : target.subject.build_context_event
        )
      end

      def append_semantic_reason(reasons, source:, target:)
        source_keys = source.surface.produces.map(&:impact_key) + source.surface.may_affect.map(&:impact_key)
        target_keys = target.surface.consumes.map(&:impact_key) + target.surface.assumes.map(&:impact_key)
        matches = source_keys.intersection(target_keys).uniq.sort_by(&:b)
        return if matches.empty?

        reasons << ImpactReasonV1.new(
          kind: "semantic_key_match",
          matches:,
          source_evidence: source.subject.surface_event,
          target_evidence: target.subject.surface_event
        )
      end

      def changed_paths(evidence)
        evidence.candidate.manifest.files.flat_map do |file|
          case file.status
          when "added", "copied" then [ file.new_path ]
          when "renamed" then [ file.old_path, file.new_path ]
          else [ file.old_path ]
          end
        end.compact.uniq.sort_by(&:b)
      end

      def observed_paths(evidence)
        evidence.candidate.build_context&.inputs&.map(&:path)&.uniq&.sort_by(&:b) || []
      end
    end
  end
end
