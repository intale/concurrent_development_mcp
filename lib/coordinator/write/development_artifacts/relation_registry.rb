# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationRegistry
      ALL_TARGETS = Types::DEVELOPMENT_ARTIFACT_CANONICAL_TARGET_KINDS
      INTERNAL_TARGETS = (ALL_TARGETS - %w[external]).freeze

      DEFINITIONS = [
        RelationDefinitionV1.new(
          relation: "documents",
          target_kinds: ALL_TARGETS,
          inverse: "documented_by",
          transitive: false,
          supersedable: true
        ),
        RelationDefinitionV1.new(
          relation: "evidences",
          target_kinds: INTERNAL_TARGETS,
          inverse: "evidenced_by",
          transitive: false,
          supersedable: true
        ),
        RelationDefinitionV1.new(
          relation: "derived_from",
          target_kinds: %w[artifact external],
          inverse: "source_of",
          transitive: true,
          supersedable: true
        ),
        RelationDefinitionV1.new(
          relation: "supersedes",
          target_kinds: %w[artifact],
          inverse: "superseded_by",
          transitive: true,
          supersedable: false
        ),
        RelationDefinitionV1.new(
          relation: "references",
          target_kinds: ALL_TARGETS,
          inverse: "referenced_by",
          transitive: false,
          supersedable: true
        ),
        RelationDefinitionV1.new(
          relation: "contains",
          target_kinds: %w[artifact],
          inverse: "contained_by",
          transitive: true,
          supersedable: true
        ),
        RelationDefinitionV1.new(
          relation: "produced_by_import",
          target_kinds: %w[operation_batch],
          inverse: "produced",
          transitive: false,
          supersedable: true
        )
      ].each(&:freeze).freeze

      BY_RELATION = DEFINITIONS.to_h { [ _1.relation, _1 ] }.freeze

      def fetch(relation)
        BY_RELATION.fetch(relation)
      end
    end
  end
end
