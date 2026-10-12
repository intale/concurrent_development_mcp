# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RecordWorkIntentionRenewalOutcome < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :renewal_id, Types::UuidV7
      attribute :intention_id, Types::UuidV7
      attribute :renewal_event, EventReference.optional
      attribute :failure, WorkIntentionRenewals::MemberFailureV1.optional
    end
  end
end
