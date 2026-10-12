# frozen_string_literal: true

module Coordinator::Write
  module Events::OptimisticSagas
    class WorkIntentionRenewalFailedV1 < Events::Base
      contract type: "WorkIntentionRenewalFailed", version: 1

      attribute :renewal_id, Types::UuidV7
      attribute :intention_id, Types::UuidV7
      attribute :reason_code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
      attribute :attempts, Types::Integer.constrained(gteq: 1, lteq: 3)
    end
  end
end
