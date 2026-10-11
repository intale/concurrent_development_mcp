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
        @in_flight = InFlight.new
      end

      def call(event)
        session = Runtime.current
        return @handler.call(event) unless session

        attributes = Runtime.safely(:subscription_attributes) do
          Coordinator::Container["observability.inventory"].subscription_attributes(definition:, event_type: event.type)
        end
        return @handler.call(event) unless attributes

        token = Runtime.safely(:subscription_tracking) { @in_flight.enter(attributes) }
        observe(session, attributes, event)
        invocation = Runtime.safely(:subscription_invocation) do
          Invocation.new(session:, prefix: :subscription,
                         name: "subscription #{attributes.fetch('subscription.set')}/#{attributes.fetch('subscription.name')}", attributes:)
        end
        invocation ? invocation.call(outcome: method(:outcome)) { @handler.call(event) } : @handler.call(event)
      ensure
        Runtime.safely(:subscription_tracking) { @in_flight.leave(attributes, token) } if token
      end

      private

      def observe(session, attributes, event)
        Runtime.safely(:subscription_oldest_in_flight) do
          session.register_observer(:subscription_oldest_in_flight, attributes:) { @in_flight.oldest_age(attributes) }
        end
        Runtime.safely(:subscription_delivery_age) do
          session.record(:subscription_delivery_age, [ Time.now - event.created_at, 0.0 ].max, attributes:)
        end
        nil
      end

      def outcome(_result)
        "ok"
      end
    end
  end
end
