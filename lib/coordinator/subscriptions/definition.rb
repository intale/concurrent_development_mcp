# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class Definition < Value
      attribute :set_name, Types::Identifier
      attribute :subscription_name, Types::Identifier
      attribute :stream_context, Types::Identifier
      attribute :stream_name, Types::Identifier
      attribute :event_type, Types::Identifier

      def options
        {
          filter: {
            streams: [ { context: stream_context, stream_name: } ],
            event_types: [ event_type ]
          }
        }
      end
    end
  end
end
