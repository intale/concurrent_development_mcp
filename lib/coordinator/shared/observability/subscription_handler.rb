# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    # Decorates the application's handler, not pg_eventstore's lifecycle.
    # A successful delivery is technical success, not command acceptance.
    class SubscriptionHandler
      attr_reader :definition

      def initialize(definition:, handler:)
        @definition = definition
        @handler = handler
        @delivery = SubscriptionDelivery.new(definition:)
      end

      def call(event)
        @delivery.call([ event ]) { @handler.call(event) }
      end
    end
  end
end
