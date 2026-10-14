# frozen_string_literal: true

module Coordinator::Shared
  module Subscriptions
    class Registration
      attr_reader :definition, :handler, :in_batches

      def initialize(definition:, handler:, pull_interval: 1.0, in_batches: false)
        @definition = definition
        @handler = if in_batches
                     Observability::BatchSubscriptionHandler.new(definition:, handler:)
        else
                     Observability::SubscriptionHandler.new(definition:, handler:)
        end
        @pull_interval = pull_interval
        @in_batches = in_batches
      end

      def register(manager)
        manager.subscribe(
          definition.subscription_name,
          handler: @handler,
          options: definition.options,
          pull_interval: @pull_interval,
          in_batches: @in_batches
        )
      end
    end
  end
end
