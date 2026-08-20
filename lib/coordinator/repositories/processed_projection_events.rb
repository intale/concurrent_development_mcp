# frozen_string_literal: true

module Coordinator
  module Repositories
    class ProcessedProjectionEvents
      IDENTITY_INDEX = "idx_processed_projection_events_identity"

      def claim(definition:, identity:, processed_at:)
        result = ReadModels::ProcessedProjectionEvent.insert_all(
          [
            identity.to_h.merge(
              projection_name: definition.name,
              projection_version: definition.version,
              processed_at:
            )
          ],
          unique_by: IDENTITY_INDEX,
          returning: [ "event_id" ]
        )

        result.rows.any?
      end

      def missing(definition:, barriers:)
        barriers.reject { processed?(definition:, barrier: _1) }.freeze
      end

      def processed?(definition:, barrier:)
        ReadModels::ProcessedProjectionEvent.exists?(
          projection_name: definition.name,
          projection_version: definition.version,
          stream_context: barrier.stream_context,
          stream_name: barrier.stream_name,
          stream_id: barrier.stream_id,
          stream_revision: barrier.stream_revision
        )
      end
    end
  end
end
