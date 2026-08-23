# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactRelationshipV1 < Value
    attribute :counterpart, CandidateSummaryV1
    attribute :relationship_kind, Types::CandidateImpactRelationshipKind
    attribute :reasons, Types::Array.of(CandidateImpactReasonV1).constrained(min_size: 1, max_size: 3)
  end
end
