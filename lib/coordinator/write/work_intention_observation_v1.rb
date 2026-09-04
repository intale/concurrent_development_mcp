# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionObservationV1 < Value
    attribute :state, Types.Instance(Domain::WorkIntentions::State)
    attribute :resource, Types.Instance(WorkIntentionResourceV1)
  end
end
