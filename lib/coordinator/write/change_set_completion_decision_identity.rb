# frozen_string_literal: true

module Coordinator::Write
  class ChangeSetCompletionDecisionIdentity < Value
    attribute :document, ProcessDecisions::ChangeSetCompletionV1
    attribute :compound_marker, CompoundMarker
    attribute :command_id, Types::Identifier
  end
end
