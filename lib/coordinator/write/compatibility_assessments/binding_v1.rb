# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class BindingV1 < Value
      attribute :obligation_validity_input_digest, Types::Sha256Digest
      attribute :source_candidate, CandidateBindingV1
      attribute :target_candidate, CandidateBindingV1
    end
  end
end
