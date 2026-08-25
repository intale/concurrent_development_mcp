# frozen_string_literal: true

module Coordinator::Write
  class DependencySatisfactionDecisionIdentity < Value
    attribute :document, ProcessDecisions::DependencySatisfactionV1
    attribute :compound_marker, CompoundMarker
    attribute :command_id, Types::Identifier
  end
end
