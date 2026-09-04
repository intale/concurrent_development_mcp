# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligations
      class State < Value
        attribute :source, Coordinator::Write::CandidateObligations::CandidateEvidenceV2
        attribute :target, Coordinator::Write::CandidateObligations::CandidateEvidenceV2
        attribute :policy, Coordinator::Write::CandidateObligations::PolicyObservationV1
        attribute :existing, VerificationObligations::DefinitionV2.optional
      end
    end
  end
end
