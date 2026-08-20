# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class ReadModelSet
      SET_NAME = "coordinator-read-models-v1"

      def initialize(
        manager:,
        registrations:,
        contract: Contracts::SubscriptionSetRegistrations.new
      )
        verify_registrations!(registrations, contract:)
        @manager = manager
        registrations.each { _1.register(@manager) }
      end

      def start
        @manager.start!
      end

      def stop
        @manager.stop
        nil
      end

      def subscription_names
        @manager.subscriptions.map(&:name).sort.freeze
      end

      def processed_event_count(subscription_name)
        subscription = @manager.subscriptions.find { _1.name == subscription_name }
        subscription&.total_processed_events || 0
      end

      private

      def verify_registrations!(registrations, contract:)
        result = contract.call(set_name: SET_NAME, registrations:)
        raise InvalidSubscriptionSet, result.errors.to_h.inspect if result.failure?
      end
    end
  end
end
