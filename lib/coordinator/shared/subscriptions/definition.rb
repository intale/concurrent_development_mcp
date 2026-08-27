# frozen_string_literal: true

module Coordinator::Shared
  module Subscriptions
    class Definition < Value
      attribute :set_name, Types::Identifier
      attribute :subscription_name, Types::Identifier
      attribute :stream_context, Types::Identifier
      attribute :stream_name, Types::Identifier
      attribute :event_types, Types::Array.of(Types::Identifier).constrained(min_size: 1, max_size: 100)
      attribute :event_markers, Types::Array.of(Types::Marker).constrained(max_size: 32).default([].freeze)

      def identity
        Identity.new(set_name:, subscription_name:)
      end

      def options
        {
          filter: {
            streams: [ { context: stream_context, stream_name: } ],
            event_types: event_type_filters
          }
        }
      end

      private

      def event_type_filters
        return event_types if event_markers.empty?

        event_types.map { |type| { type:, markers: event_markers } }
      end
    end
  end
end
