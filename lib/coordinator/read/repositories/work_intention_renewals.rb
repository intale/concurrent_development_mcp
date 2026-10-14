# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class WorkIntentionRenewals
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
    end
  end
end
