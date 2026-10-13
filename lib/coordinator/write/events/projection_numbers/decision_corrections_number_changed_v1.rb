# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class DecisionCorrectionsNumberChangedV1 < Coordinator::Write::Events::Base
    contract type: "DecisionCorrectionsNumberChanged", version: 1

    attribute :decision_id, Coordinator::Write::Types::Identifier
    attribute :corrections_number, Coordinator::Write::Types::Integer.constrained(gteq: 0)
  end
end
