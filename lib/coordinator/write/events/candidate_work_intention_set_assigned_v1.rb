# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateWorkIntentionSetAssignedV1 < Base
      contract type: "CandidateWorkIntentionSetAssigned", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :intention_set_id, Types::UuidV7
    end
  end
end
