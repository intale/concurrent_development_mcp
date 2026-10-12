# frozen_string_literal: true

module Coordinator::Write
  module Events::OptimisticSagas
    class WorkIntentionRenewalAssignedV1 < Events::Base
      contract type: "WorkIntentionRenewalAssigned", version: 1

      attribute :renewal_id, Types::UuidV7
      attribute :position, Types::Integer.constrained(gteq: 0, lteq: 31)
      attribute :intention_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :fencing_token, Types::FencingToken
      attribute :renew_command_id, Types::UuidV7
      attribute :outcome_command_id, Types::UuidV7
    end
  end
end
