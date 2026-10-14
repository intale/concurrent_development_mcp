# frozen_string_literal: true

module Coordinator::Read::Subscriptions
  class BatchRegistration < Coordinator::Shared::Subscriptions::Registration
    def initialize(definition:, handler:, pull_interval: 1.0)
      super(definition:, handler:, pull_interval:, in_batches: true)
    end
  end
end
