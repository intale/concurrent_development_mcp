# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CoordContexts
      def initialize(state_loader: Projections::CoordContextStateLoader.new)
        @state_loader = state_loader
      end

      class AttemptHistoryRecord < ApplicationRecord
        self.table_name = "attempt_histories"
        self.primary_key = "attempt_id"
      end
      private_constant :AttemptHistoryRecord

      def fetch(change_set_id)
        record = Coordinator::Read::CoordContext.find_by(change_set_id:)
        build_snapshot(record)
      end

      def resolve(scope_kind:, scope_id:)
        scope = Coordinator::Read::CoordContextScope.find_by(scope_kind:, scope_id:)
        return unless scope

        fetch(scope.change_set_id)
      end

      def store_attempt_event(event:, payload:)
        case payload
        when Coordinator::Write::Events::AttemptAuthorizedV1
          store_attempt_authorized(event:, payload:)
        when Coordinator::Write::Events::AttemptStartedV1
          update_attempt_started(payload)
        when Coordinator::Write::Events::AttemptAbandonedV2
          update_attempt_abandoned(event:, payload:)
        when Coordinator::Write::Events::AttemptCompletedV1
          update_attempt_completed(event:, payload:)
        end

        nil
      end

      def attempt_page(work_item_id:, after_authorized_global_position:, limit:)
        relation = AttemptHistoryRecord.where(work_item_id:)
        if after_authorized_global_position
          relation = relation.where("authorized_global_position > ?", after_authorized_global_position)
        end
        records = relation.order(:authorized_global_position, :attempt_id).limit(limit + 1).to_a
        has_more = records.length > limit
        items = records.first(limit).map { build_attempt_history(_1) }

        QueryResultV1::AttemptHistoryPage.new(
          work_item_id:,
          items:,
          next_authorized_global_position: has_more ? items.last.authorized_global_position : nil,
          has_more:
        )
      end

      private

      def store_attempt_authorized(event:, payload:)
        record = AttemptHistoryRecord.find_or_initialize_by(attempt_id: payload.attempt_id)
        if record.persisted?
          verify_authorization!(record, event:, payload:)
          return
        end

        record.assign_attributes(
          change_set_id: payload.change_set_id,
          work_item_id: payload.work_item_id,
          agent_id: payload.agent_id,
          base_snapshots: payload.base_snapshots.map(&:to_h),
          status: "authorized",
          authorization_event: event_reference(event).to_h,
          authorized_global_position: event.global_position,
          authorized_at_domain: payload.authorized_at
        )
        record.save!
      end

      def update_attempt_started(payload)
        record = attempt_history!(payload)
        return if record.started_at_domain&.utc&.iso8601(6) == payload.started_at

        record.update!(
          status: terminal_status?(record.status) ? record.status : "started",
          started_at_domain: payload.started_at
        )
      end

      def update_attempt_abandoned(event:, payload:)
        record = attempt_history!(payload)
        if record.status == "completed"
          raise ProjectionStateError, "Completed Attempt #{payload.attempt_id} cannot be abandoned"
        end

        record.update!(
          status: "abandoned",
          abandonment_reason: payload.reason,
          terminal_event: event_reference(event).to_h,
          terminal_at_domain: payload.abandoned_at
        )
      end

      def update_attempt_completed(event:, payload:)
        record = attempt_history!(payload)
        if record.status == "abandoned"
          raise ProjectionStateError, "Abandoned Attempt #{payload.attempt_id} cannot be completed"
        end

        record.update!(
          status: "completed",
          selected_candidate_id: payload.candidate_id,
          selected_candidate_event: payload.candidate_event.to_h,
          terminal_event: event_reference(event).to_h,
          terminal_at_domain: payload.completed_at
        )
      end

      def verify_authorization!(record, event:, payload:)
        expected = {
          change_set_id: payload.change_set_id,
          work_item_id: payload.work_item_id,
          agent_id: payload.agent_id,
          base_snapshots: payload.base_snapshots.map(&:to_h),
          authorization_event: event_reference(event).to_h,
          authorized_global_position: event.global_position,
          authorized_at_domain: Time.iso8601(payload.authorized_at)
        }
        actual = expected.keys.to_h do |attribute|
          value = record.public_send(attribute)
          value = deep_symbolize(value) if value.is_a?(Hash) || value.is_a?(Array)
          [ attribute, value ]
        end
        return if actual == expected

        raise ProjectionStateError, "Attempt #{payload.attempt_id} authorization evidence changed"
      end

      def attempt_history!(payload)
        record = AttemptHistoryRecord.find_by(attempt_id: payload.attempt_id)
        raise ProjectionStateError, "Attempt #{payload.attempt_id} authorization is not projected" unless record
        unless record.change_set_id == payload.change_set_id && record.work_item_id == payload.work_item_id
          raise ProjectionStateError, "Attempt #{payload.attempt_id} history scope changed"
        end

        record
      end

      def terminal_status?(status)
        %w[abandoned completed].include?(status)
      end

      def build_attempt_history(record)
        QueryResultV1::AttemptHistoryView.new(
          attempt_id: record.attempt_id,
          change_set_id: record.change_set_id,
          work_item_id: record.work_item_id,
          agent_id: record.agent_id,
          base_snapshots: record.base_snapshots.map do
            Coordinator::Write::RepositorySnapshotV1.new(deep_symbolize(_1))
          end,
          status: record.status,
          authorization_event: Coordinator::Write::EventReference.new(deep_symbolize(record.authorization_event)),
          authorized_global_position: record.authorized_global_position,
          authorized_at: record.authorized_at_domain.utc.iso8601(6),
          started_at: record.started_at_domain&.utc&.iso8601(6),
          selected_candidate_id: record.selected_candidate_id,
          selected_candidate_event: record.selected_candidate_event &&
            Coordinator::Write::EventReference.new(deep_symbolize(record.selected_candidate_event)),
          abandonment_reason: record.abandonment_reason,
          terminal_event: record.terminal_event &&
            Coordinator::Write::EventReference.new(deep_symbolize(record.terminal_event)),
          terminal_at: record.terminal_at_domain&.utc&.iso8601(6)
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

      def build_snapshot(record)
        return unless record

        CoordContextSnapshot.new(
          state: @state_loader.call(record.document),
          source_positions: record.source_positions.map do |position|
            ProjectionBarrier.new(deep_symbolize(position))
          end,
          last_processed_at: record.last_processed_at.utc.iso8601(6)
        )
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array
          value.map { deep_symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
