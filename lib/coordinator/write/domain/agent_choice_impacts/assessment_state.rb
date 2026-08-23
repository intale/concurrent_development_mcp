# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoiceImpacts
      class AssessmentState < Value
        attribute :choice, Coordinator::Write::AgentChoiceImpacts::ChoiceSnapshotV1
        attribute :attempt, Attempts::State
        attribute :reconstruction, Coordinator::Write::AgentChoiceImpacts::ReconstructionV1
      end
    end
  end
end
