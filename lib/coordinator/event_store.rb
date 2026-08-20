# frozen_string_literal: true

module Coordinator
  class EventStore
    def initialize(client:, pg_stream_factory: PgStreamFactory.new)
      @client = client
      @pg_stream_factory = pg_stream_factory
    end

    def multiple(&block)
      @client.multiple(&block)
    end

    def read(reference, criteria)
      stream = @pg_stream_factory.call(reference)

      events = @client.read(
        stream,
        options: {
          direction: criteria.direction,
          max_count: criteria.query_max_count,
          filter: { event_types: criteria.event_types }
        }
      )
      return events if events.length <= criteria.maximum_count

      raise EventHistoryLimitExceeded,
            "Event read exceeded #{criteria.maximum_count} relevant events for #{reference.to_h.inspect}"
    rescue PgEventstore::StreamNotFoundError
      []
    end

    def read_grouped(reference, criteria)
      stream = @pg_stream_factory.call(reference)

      @client.read_grouped(
        stream,
        options: {
          direction: criteria.direction,
          filter: { event_types: criteria.event_types }
        }
      )
    rescue PgEventstore::StreamNotFoundError
      []
    end

    def append(reference, events)
      stream = @pg_stream_factory.call(reference)

      @client.append_to_stream(stream, events)
    end
  end
end
