# frozen_string_literal: true

module Coordinator::Shared
  module Subscriptions
    class Registration
      attr_reader :definition, :handler

      def initialize(definition:, handler:, pull_interval: 1.0)
        @definition = definition
        @handler = Observability::SubscriptionHandler.new(definition:, handler:)
        @pull_interval = pull_interval
      end

      def register(manager)
        manager.subscribe(
          definition.subscription_name,
          handler: @handler,
          options: definition.options,
          pull_interval: @pull_interval
        )
      end
    end
  end
end
