# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class EvidenceCollectorV1 < Value
      attribute :kind, Types::ActorKind
      attribute :id, Types::Identifier
      attribute :collector_version, Types::CandidateCollectorVersion
    end
  end
end
