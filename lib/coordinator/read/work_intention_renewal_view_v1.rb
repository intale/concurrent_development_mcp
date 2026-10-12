# frozen_string_literal: true

module Coordinator::Read
  class WorkIntentionRenewalViewV1 < Value
    class Failure < Value
      attribute :reason_code, Types::Identifier
      attribute :reason, Types::String
      attribute :retryable, Types::Strict::Bool
      attribute :attempts, Types::Integer.constrained(gteq: 1, lteq: 3)
    end

    class Member < Value
      attribute :position, Types::Integer.constrained(gteq: 0, lteq: 31)
      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :fencing_token, Types::Integer.constrained(gteq: 1)
      attribute :status, Types::String.enum("pending", "completed", "failed")
      attribute :renewal_event, Coordinator::Write::EventReference.optional
      attribute :failure, Failure.optional
    end

    attribute :renewal_id, Types::UuidV7
    attribute :task_id, Types::UuidV7.optional
    attribute :intention_set_id, Types::UuidV7
    attribute :attempt_id, Types::Identifier
    attribute :status, Types::String.enum("requested", "running", "completed", "failed")
    attribute :expires_at, Types::Timestamp
    attribute :actor, AttributedActorV1
    attribute :correlation_id, Types::UuidV7
    attribute :members, Types::Array.of(Member).constrained(max_size: 32)
    attribute :updated_at, Types::Timestamp
  end
end
