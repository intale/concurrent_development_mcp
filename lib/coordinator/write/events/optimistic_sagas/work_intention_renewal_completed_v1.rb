# frozen_string_literal: true

module Coordinator::Write
  module Events::OptimisticSagas
    class WorkIntentionRenewalCompletedV1 < Events::Base
      contract type: "WorkIntentionRenewalCompleted", version: 1

      attribute :renewal_id, Types::UuidV7
      attribute :intention_id, Types::UuidV7
      attribute :renewal_event, EventReference.optional
    end
  end
end
