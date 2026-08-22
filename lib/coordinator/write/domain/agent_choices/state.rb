# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module AgentChoices
      class State < Value
        attribute :attempt, Attempts::State
        attribute :existing_choice, EventReference.optional
        attribute :current_context, DecisionContexts::ContextV1
        attribute :resolution, DecisionContexts::ResultV1
      end
    end
  end
end
