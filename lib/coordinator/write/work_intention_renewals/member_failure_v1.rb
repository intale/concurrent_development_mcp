# frozen_string_literal: true

module Coordinator::Write
  module WorkIntentionRenewals
    class MemberFailureV1 < Value
      attribute :reason_code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
      attribute :attempts, Types::Integer.constrained(gteq: 1, lteq: 3)
    end
  end
end
