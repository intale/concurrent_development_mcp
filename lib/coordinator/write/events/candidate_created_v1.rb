# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateCreatedV1 < Base
      contract type: "CandidateCreated", version: 1

      attribute :candidate_id, Types::Identifier
    end
  end
end
