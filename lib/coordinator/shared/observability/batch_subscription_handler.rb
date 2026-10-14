# frozen_string_literal: true

module Coordinator::Shared::Observability
  class BatchSubscriptionHandler
    attr_reader :definition

    def initialize(definition:, handler:)
      @definition, @handler = definition, handler
      @delivery = SubscriptionDelivery.new(definition:, in_batches: true)
    end

    def call(events)
      @delivery.call(events) { @handler.call(events) }
    end
  end
end
