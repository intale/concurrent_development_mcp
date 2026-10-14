# frozen_string_literal: true

module Coordinator::Shared::Observability
  # Counts callbacks separately from delivered events, including native retries.
  # No source content or caller identifiers enter telemetry dimensions.
  class SubscriptionDelivery
    def initialize(definition:, in_batches: false)
      @definition, @in_batches = definition, in_batches
      @in_flight = InFlight.new
    end

    def call(events)
      session = Runtime.current
      return yield unless session

      attributes = Runtime.safely(:subscription_attributes) do
        inventory.subscription_attributes(definition: @definition, event_type: @in_batches ? "batch" : events.first.type)
      end
      return yield unless attributes

      token = Runtime.safely(:subscription_tracking) { @in_flight.enter(attributes) }
      observe(session, attributes, events)
      invocation = Runtime.safely(:subscription_invocation) do
        Invocation.new(session:, prefix: :subscription,
          name: "subscription #{attributes.fetch('subscription.set')}/#{attributes.fetch('subscription.name')}",
          attributes: span_attributes(attributes, events))
      end
      invocation ? invocation.call(outcome: method(:outcome)) { yield } : yield
    ensure
      Runtime.safely(:subscription_tracking) { @in_flight.leave(attributes, token) } if token
    end

    private

    def observe(session, attributes, events)
      Runtime.safely(:subscription_oldest_in_flight) do
        session.register_observer(:subscription_oldest_in_flight, attributes:) { @in_flight.oldest_age(attributes) }
      end
      Runtime.safely(:subscription_delivery_age) do
        oldest = events.map(&:created_at).min
        session.record(:subscription_delivery_age, [ Time.now - oldest, 0.0 ].max, attributes:) if oldest
      end
      Runtime.safely(:subscription_delivered) do
        events.group_by(&:type).each do |type, delivered|
          labels = inventory.subscription_attributes(definition: @definition, event_type: type)
          session.record(:subscription_delivered, delivered.length, attributes: labels)
        end
      end
      nil
    end

    def span_attributes(attributes, events)
      return attributes unless @in_batches

      types = events.map do |event|
        inventory.subscription_attributes(definition: @definition, event_type: event.type).fetch("event.type")
      end.uniq.sort
      attributes.merge("event.count" => events.length.to_s, "event.types" => types.join(","))
    end

    def inventory
      Coordinator::Container["observability.inventory"]
    end

    def outcome(_result)
      "ok"
    end
  end
end
