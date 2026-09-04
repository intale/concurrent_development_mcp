# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateCheckpointKindSelectedV1 < Base
      contract type: "CandidateCheckpointKindSelected", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :checkpoint_kind, Types::CandidateCheckpointKind
    end
  end
end
