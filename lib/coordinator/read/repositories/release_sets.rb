# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class ReleaseSets
      def fetch(release_set_id)
        record = Coordinator::Read::ReleaseSet.find_by(release_set_id:)
        record && build_view(record)
      end

      def store(event:, release_set:)
        Coordinator::Read::ReleaseSet.create!(
          release_set_id: release_set.release_set_id,
          change_set_id: release_set.change_set_id,
          ordered_members: release_set.ordered_members.map(&:to_h),
          release_digest: release_set.release_digest,
          status: "prepared",
          preparation_policy_version: release_set.policy_version,
          prepared_at_domain: release_set.prepared_at,
          prepared_event: event_reference(event).to_h,
          prepared_actor: actor(event).to_h,
          prepared_markers: event.markers,
          prepared_metadata: event.metadata,
          prepared_causation_id: event.causation_id,
          prepared_correlation_id: event.correlation_id,
          prepared_global_position: event.global_position,
          prepared_at_store: event.created_at
        )
      end

      private

      def build_view(record)
        ReleaseSetViewV1.new(
          release_set_id: record.release_set_id,
          change_set_id: record.change_set_id,
          ordered_members: record.ordered_members.map do |member|
            Coordinator::Write::ReleaseSets::MemberEvidenceV1.new(symbolize(member))
          end,
          release_digest: record.release_digest,
          status: record.status,
          preparation_policy_version: record.preparation_policy_version,
          prepared_at: record.prepared_at_domain.utc.iso8601(6),
          prepared: source_evidence(record)
        )
      end

      def source_evidence(record)
        ReleaseSetSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.prepared_event)),
          actor: AttributedActorV1.new(symbolize(record.prepared_actor)),
          markers: record.prepared_markers,
          metadata: record.prepared_metadata,
          global_position: record.prepared_global_position,
          occurred_at: record.prepared_at_domain.utc.iso8601(6),
          persisted_at: record.prepared_at_store.utc.iso8601(6),
          causation_id: record.prepared_causation_id,
          correlation_id: record.prepared_correlation_id
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
