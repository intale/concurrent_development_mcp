# frozen_string_literal: true

module Coordinator::Write
  module Middlewares
    class RootCorrelationEventTracing < PgEventstore::Middleware::EventTracing
      def serialize(event)
        return super unless event.correlation_id && !event.caused_by

        event.metadata[self.class::CORRELATION_ID_KEY] = event.correlation_id
        event.feature_markers.push(self.class.correlation_marker(event.correlation_id))
        nil
      end
    end
  end
end
