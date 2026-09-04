# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateSubmittedV3 < Base
      contract type: "CandidateSubmitted", version: 3

      attribute :candidate_id, Types::Identifier
    end
  end
end
