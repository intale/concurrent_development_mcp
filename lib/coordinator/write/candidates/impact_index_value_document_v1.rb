# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactIndexValueDocumentV1 < Value
      SCHEMA = "candidate-impact-bucket-value/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :kind, Types::CandidateImpactIndexKind
      attribute :value, Types::String.constrained(min_size: 1, max_size: 1_024)
    end
  end
end
