# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ResultV1 < Value
      attribute :outcome, Types::CandidateObligationDecisionOutcome
      attribute :obligation_id, Types::Identifier
      attribute :event, EventReference.optional
    end
  end
end
