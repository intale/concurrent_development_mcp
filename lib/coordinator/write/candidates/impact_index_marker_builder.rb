# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactIndexMarkerBuilder
      POLICY_VERSION = "candidate-impact-exact-index/v2"

      def initialize(
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @compound_marker_builder = compound_marker_builder
      end

      def call(evidence:, surface:)
        call_documents(
          repository_id: evidence.candidate.repository_id,
          manifest: evidence.manifest,
          build_context: evidence.build_context,
          surface:
        )
      end

      def call_documents(repository_id:, manifest:, build_context:, surface:)
        (role_markers(
          role: "source",
          repository_id:,
          manifest:,
          build_context:,
          surface:
        ) + role_markers(
          role: "target",
          repository_id:,
          manifest:,
          build_context:,
          surface:
        )).uniq.sort_by(&:b).freeze
      end

      def counterpart(evidence:, surface:, direction:)
        role = direction == "outgoing" ? "target" : "source"
        values_role = direction == "outgoing" ? "source" : "target"

        role_markers(
          role:,
          repository_id: evidence.candidate.repository_id,
          manifest: evidence.manifest,
          build_context: evidence.build_context,
          surface:,
          values_role:
        ).freeze
      end

      private

      def role_markers(role:, repository_id:, manifest:, build_context:, surface:, values_role: role)
        paths = path_values(manifest, build_context, values_role)
        semantics = semantic_values(surface, values_role)

        (
          build_markers(role:, kind: "path", values: paths, repository_id:) +
          build_markers(role:, kind: "semantic", values: semantics, repository_id: nil)
        ).uniq.sort_by(&:b)
      end

      def path_values(manifest, build_context, role)
        changed = changed_paths(manifest)
        return changed if role == "source"

        changed + (build_context&.inputs&.map(&:path) || [])
      end

      def semantic_values(surface, role)
        return surface.produces.map(&:impact_key) + surface.may_affect.map(&:impact_key) if role == "source"

        surface.consumes.map(&:impact_key) + surface.assumes.map(&:impact_key)
      end

      def build_markers(role:, kind:, values:, repository_id:)
        values.uniq.map do |value|
          components = [
            "role:#{role}",
            "kind:#{kind}",
            "value:#{value}",
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
