# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class ReadModelDefinition < Value
      attribute :set_name, Types::Identifier
      attribute :subscription_name, Types::Identifier
      attribute :streams,
                Types::Array.of(Coordinator::Shared::Subscriptions::StreamFilter).constrained(min_size: 1, max_size: 10)
      attribute :event_types, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 100)

      def identity
        Coordinator::Shared::Subscriptions::Identity.new(set_name:, subscription_name:)
      end

      def options
        {
          filter: {
            streams: streams.map(&:to_h),
            event_types:
          }
        }
      end
    end
  end
end
