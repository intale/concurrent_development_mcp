# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactReasonV1 < Value
    attribute :kind, Types::CandidateImpactReasonKind
    attribute :matches, Types::Array.of(Types::String.constrained(min_size: 1, max_size: 1_024))
                                    .constrained(min_size: 1, max_size: 256)
    attribute :source_evidence, CandidateSourceEvidenceV1
    attribute :target_evidence, CandidateSourceEvidenceV1
  end
end
