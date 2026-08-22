# frozen_string_literal: true

module Coordinator::Write
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

    def read_marked(reference, criteria)
      stream = @pg_stream_factory.call(reference)

      events = @client.read(
        stream,
        options: {
          direction: criteria.direction,
          max_count: criteria.query_max_count,
          filter: {
            event_types: [ { type: criteria.event_type, markers: [ criteria.marker ] } ]
          }
        }
      )
      return events if events.length <= criteria.maximum_count

      raise EventHistoryLimitExceeded,
            "Marked event read exceeded #{criteria.maximum_count} relevant events for #{reference.to_h.inspect}"
    rescue PgEventstore::StreamNotFoundError
      []
    end

    def append(reference, events, expected_revision: nil)
      stream = @pg_stream_factory.call(reference)
      options = expected_revision.nil? ? {} : { expected_revision: }

      @client.append_to_stream(stream, events, options:)
    end
  end
end
