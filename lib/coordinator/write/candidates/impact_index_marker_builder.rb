# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactIndexMarkerBuilder
      POLICY_VERSION = "candidate-impact-bucket-index/v1"

      def initialize(
        canonical_json: CanonicalJson.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @canonical_json = canonical_json
        @compound_marker_builder = compound_marker_builder
      end

      def call(evidence:, surface:)
        repository_id = evidence.submission.repository_id
        changed = changed_paths(evidence.manifest)
        observed = evidence.build_context&.inputs&.map(&:path) || []
        source_semantic = surface.produces.map(&:impact_key) + surface.may_affect.map(&:impact_key)
        target_semantic = surface.consumes.map(&:impact_key) + surface.assumes.map(&:impact_key)

        markers = []
        markers.concat(build_markers(role: "source", kind: "path", values: changed, repository_id:))
        markers.concat(build_markers(role: "target", kind: "path", values: changed + observed, repository_id:))
        markers.concat(build_markers(role: "source", kind: "semantic", values: source_semantic, repository_id: nil))
        markers.concat(build_markers(role: "target", kind: "semantic", values: target_semantic, repository_id: nil))
        markers.uniq.sort_by(&:b).freeze
      end

      private

      def build_markers(role:, kind:, values:, repository_id:)
        values.uniq.map { bucket(kind:, value: _1) }.uniq.map do |bucket|
          components = [
            "role:#{role}",
            "kind:#{kind}",
            "bucket:#{bucket}",
            "index-policy:#{POLICY_VERSION}"
          ]
          components << "repository:#{repository_id}" if repository_id
          @compound_marker_builder.call(
            CompoundMarkerDefinitionV1.new(
              purpose: "candidate-impact-index",
              components:
            )
          ).marker
        end
      end

      def bucket(kind:, value:)
        document = ImpactIndexValueDocumentV1.new(
          schema: ImpactIndexValueDocumentV1::SCHEMA,
          kind:,
          value:
        )
        @canonical_json.sha256(document.to_h).delete_prefix("sha256:").slice(0)
      end

      def changed_paths(manifest)
        manifest.files.flat_map do |file|
          case file.status
          when "added", "copied" then [ file.new_path ]
          when "renamed" then [ file.old_path, file.new_path ]
          else [ file.old_path ]
          end
        end.compact.uniq.sort_by(&:b)
      end
    end
  end
end
