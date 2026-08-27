# frozen_string_literal: true

module Coordinator::Shared
  module Subscriptions
    class SetFactory
      def initialize(set_class:, set_name:, registrations:)
        @set_class = set_class
        @set_name = set_name
        @registrations = registrations
      end

      def call(manager: nil)
        manager ||= PgEventstore.subscriptions_manager(subscription_set: @set_name)
        @set_class.new(manager:, registrations: @registrations)
      end
    end
  end
end
