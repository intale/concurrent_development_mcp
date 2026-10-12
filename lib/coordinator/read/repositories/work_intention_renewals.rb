# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class WorkIntentionRenewals
      include EventTimestamped

      def fetch(renewal_id: nil, task_id: nil)
        record = Coordinator::Read::WorkIntentionRenewal.find_by(renewal_id ? { renewal_id: } : { task_id: })
        return unless record&.request_event
        WorkIntentionRenewalViewV1.new(
          renewal_id: record.renewal_id, task_id: record.task_id, intention_set_id: record.intention_set_id, attempt_id: record.attempt_id,
          status: record.status, expires_at: record.expires_at.utc.iso8601(6),
          actor: AttributedActorV1.new(kind: record.actor_kind, id: record.actor_id, authenticated: false),
          correlation_id: record.correlation_id,
          members: record.members.map { WorkIntentionRenewalViewV1::Member.new(_1.deep_symbolize_keys) },
          updated_at: record.updated_at.utc.iso8601(6))
      end

      def store(event:, payload:)
        record = Coordinator::Read::WorkIntentionRenewal.lock.find_or_initialize_by(renewal_id: payload.renewal_id)
        case payload
        when Coordinator::Write::Events::OptimisticSagas::WorkIntentionSetRenewalRequestedV1
          record.assign_attributes(intention_set_id: payload.intention_set_id, attempt_id: payload.attempt_id,
            task_id: event.metadata["task_id"],
            expires_at: payload.expires_at, actor_kind: event.metadata.fetch("actor_kind"), actor_id: event.metadata.fetch("actor_id"),
            correlation_id: event.correlation_id, request_event: reference(event))
        when Coordinator::Write::Events::OptimisticSagas::WorkIntentionRenewalAssignedV1
          unless record.members.any? { _1.fetch("intention_id") == payload.intention_id }
            record.members = (record.members + [ { "position" => payload.position, "intention_id" => payload.intention_id,
              "resource_id" => payload.resource_id, "fencing_token" => payload.fencing_token,
              "status" => "pending", "renewal_event" => nil, "failure" => nil } ]).sort_by { _1.fetch("position") }
          end
        when Coordinator::Write::Events::OptimisticSagas::WorkIntentionRenewalCompletedV1
          member_outcome(record, payload.intention_id, status: "completed", renewal_event: payload.renewal_event&.to_h, failure: nil)
        when Coordinator::Write::Events::OptimisticSagas::WorkIntentionRenewalFailedV1
          failure = payload.to_h.except(:renewal_id, :intention_id)
          member_outcome(record, payload.intention_id, status: "failed", renewal_event: nil, failure:)
          record.failure = failure
        when Coordinator::Write::Events::OptimisticSagas::WorkIntentionSetRenewalCompletedV1
          record.status = "completed"
          record.terminal_event = reference(event)
        when Coordinator::Write::Events::OptimisticSagas::WorkIntentionSetRenewalFailedV1
          record.status = "failed"
          record.terminal_event = reference(event)
        end
        save_from_event(record, event:)
      end

      private

      def member_outcome(record, intention_id, **changes)
        found = false
        record.members = record.members.map do |member|
          next member unless member.fetch("intention_id") == intention_id
          found = true
          member.merge(changes.stringify_keys.transform_values { _1.is_a?(Hash) ? _1.deep_stringify_keys : _1 })
        end
        raise ProjectionStateError, "Renewal outcome has no assigned member" unless found
        record.status = "running" unless %w[completed failed].include?(record.status)
      end

      def reference(event)
        Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
          stream_context: event.stream.context, stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id, stream_revision: event.stream_revision).to_h
      end
    end
  end
end
