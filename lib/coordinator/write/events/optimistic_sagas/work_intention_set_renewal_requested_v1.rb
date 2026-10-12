# frozen_string_literal: true

module Coordinator::Write
  module Events::OptimisticSagas
    class WorkIntentionSetRenewalRequestedV1 < Events::Base
      contract type: "WorkIntentionSetRenewalRequested", version: 1

      attribute :renewal_id, Types::UuidV7
      attribute :intention_set_id, Types::UuidV7
      attribute :attempt_id, Types::Identifier
      attribute :expires_at, Types::Timestamp
    end
  end
end
