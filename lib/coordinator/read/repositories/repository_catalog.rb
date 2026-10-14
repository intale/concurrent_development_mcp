# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class RepositoryCatalog
      def initialize(compound_marker_builder: Coordinator::Shared::CompoundMarkerBuilder.new)
        @compound_marker_builder = compound_marker_builder
      end

      def page(query, repository_key: nil)
        relation = Coordinator::Read::Repository.where(scope: query.scope)
        if repository_key
          marker = scoped_repository_key_marker(scope: query.scope, repository_key:).marker
          relation = relation.where("registered_markers @> ?::jsonb", JSON.generate([ marker ]))
        end
        relation = relation.where("repository_id > ?", query.after_repository_id) if query.after_repository_id
        rows = relation.order(:repository_id).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_summary(_1) }

        RepositoryPageV1.new(
          items:,
          next_repository_id: has_more ? items.last.repository_id : nil,
          has_more:
        )
      end

      private

      def scoped_repository_key_marker(scope:, repository_key:)
        @compound_marker_builder.call(
          Coordinator::Shared::CompoundMarkerDefinitionV1.new(
            purpose: "scoped-repository-key",
            components: [ "scope:#{scope}", "repository-key:#{repository_key}" ]
          )
        )
      end

      def build_summary(record)
        RepositorySummaryV1.new(
          repository_id: record.repository_id,
          scope: record.scope,
          display_name: record.display_name,
          paths: record.paths,
          remotes: record.remotes,
          registered: source_evidence(record)
        )
      end

      def source_evidence(record)
        RepositorySourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.registered_event)),
          actor: AttributedActorV1.new(symbolize(record.registered_actor)),
          markers: record.registered_markers,
          metadata: record.registered_metadata,
          global_position: record.registered_global_position,
          occurred_at: record.registered_at_domain.utc.iso8601(6),
          persisted_at: record.registered_at_store.utc.iso8601(6),
          causation_id: record.registered_causation_id,
          correlation_id: record.registered_correlation_id
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
