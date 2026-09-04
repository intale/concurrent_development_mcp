# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateAssignedToAttemptV1 < Base
      contract type: "CandidateAssignedToAttempt", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
    end
  end
end
