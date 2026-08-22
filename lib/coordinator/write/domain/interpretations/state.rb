# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Interpretations
      class State < Value
        attribute :source, Coordinator::Write::Interpretations::GuidanceSourceEvidenceV1.optional
        attribute :proposal_exists, Types::Bool
      end
    end
  end
end
