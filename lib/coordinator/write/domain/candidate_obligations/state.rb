# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligations
      class State < Value
        attribute :source, Coordinator::Write::CandidateObligations::CandidateEvidenceV1
        attribute :target, Coordinator::Write::CandidateObligations::CandidateEvidenceV1
        attribute :policy, Coordinator::Write::CandidateObligations::PolicyObservationV1
        attribute :existing, Events::VerificationObligationCreatedV1.optional
      end
    end
  end
end
