# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class PartitionChangeV1 < Value
      attribute :partition, Decisions::DecisionPartitionV1
      attribute :recorded_observation, DecisionContexts::PartitionObservationV1
      attribute :before_observation, DecisionContexts::PartitionObservationV1
      attribute :after_observation, DecisionContexts::PartitionObservationV1
      attribute :advancement_event, EventReference
    end
  end
end
