# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class RepositoryCatalog
      include EventTimestamped

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

      def store(event:, registration:)
        record = Coordinator::Read::Repository.lock.find_by(repository_id: registration.repository_id)
        if record
          apply_fact!(record, event, registration)
          return record
        end

        Coordinator::Read::Repository.new(registration_attributes(event, registration)).tap do |created|
          created.save!(touch: false)
        end
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

      def registration_attributes(event, registration)
        {
          repository_id: registration.repository_id,
          scope: registration.scope,
          display_name: nil,
          paths: [],
          remotes: [],
          registered_event: event_reference(event).to_h,
          registered_actor: actor(event).to_h,
          registered_markers: event.markers,
          registered_metadata: event.metadata,
          registered_causation_id: event.causation_id,
          registered_correlation_id: event.correlation_id,
          registered_global_position: event.global_position,
          registered_at_domain: event.created_at,
          registered_at_store: event.created_at,
          updated_at: event.created_at,
          created_at: event.created_at
        }
      end

      def apply_fact!(record, event, registration)
        case registration
        when Coordinator::Write::Events::RepositoryRegisteredV2
          verify_registration!(record, event, registration)
        when Coordinator::Write::Events::RepositoryDisplayNameChangedV1
          record.display_name = registration.display_name
        when Coordinator::Write::Events::RepositoryPathAddedV1
          record.paths = (record.paths + [ registration.path ]).uniq
        when Coordinator::Write::Events::RepositoryPathRemovedV1
          record.paths = record.paths - [ registration.path ]
        when Coordinator::Write::Events::RepositoryRemoteAddedV1
          record.remotes = (record.remotes + [ registration.remote ]).uniq
        when Coordinator::Write::Events::RepositoryRemoteRemovedV1
          record.remotes = record.remotes - [ registration.remote ]
        end
        save_from_event(record, event:) if record.persisted?
        record
      end

      def verify_registration!(record, event, registration)
        matches = record.scope == registration.scope &&
                  record.registered_event.fetch("event_id") == event.id
        return if matches

        raise ProjectionStateError, "Repository identity changed within its source stream"
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

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
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
