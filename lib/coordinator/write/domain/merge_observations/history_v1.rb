# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeObservations
      class HistoryV1 < Value
        attribute :authorization, Coordinator::Write::MergeAuthorizations::DecisionEvidenceV2.optional
        attribute :current_evaluation,
                  Coordinator::Write::MergeAuthorizations::EvaluationV1.optional
        attribute :existing_observation, Events::MergeObservedV2.optional
        attribute :existing_observation_event, EventReference.optional
      end
    end
  end
end
