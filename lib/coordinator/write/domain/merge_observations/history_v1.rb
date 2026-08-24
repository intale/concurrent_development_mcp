# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module MergeObservations
      class HistoryV1 < Value
        attribute :authorization, Events::MergeAuthorizationGrantedV1.optional
        attribute :authorization_event, EventReference.optional
        attribute :current_evaluation,
                  Coordinator::Write::MergeAuthorizations::EvaluationV1.optional
        attribute :existing_observation, Events::MergeObservedV1.optional
        attribute :existing_observation_event, EventReference.optional
      end
    end
  end
end
