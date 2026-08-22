# frozen_string_literal: true

module Coordinator::Shared
  module Subscriptions
    class Definition < Value
      attribute :set_name, Types::Identifier
      attribute :subscription_name, Types::Identifier
      attribute :stream_context, Types::Identifier
      attribute :stream_name, Types::Identifier
      attribute :event_types, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 100)

      def identity
        Identity.new(set_name:, subscription_name:)
      end

      def options
        {
          filter: {
            streams: [ { context: stream_context, stream_name: } ],
            event_types:
          }
        }
      end
    end
  end
end
