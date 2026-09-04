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

      options = {
        direction: criteria.direction,
        max_count: criteria.query_max_count,
        filter: { event_types: criteria.event_types }
      }
      options[:from_revision] = criteria.from_revision unless criteria.from_revision.nil?
      options[:to_revision] = criteria.to_revision unless criteria.to_revision.nil?
      events = @client.read(stream, options:)
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

    def read_at(reference, stream_revision)
      stream = @pg_stream_factory.call(reference)
      event = @client.read(
        stream,
        options: {
          direction: :asc,
          from_revision: stream_revision,
          max_count: 1
        }
      ).first

      event if event&.stream_revision == stream_revision
    rescue PgEventstore::StreamNotFoundError
      nil
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

    def read_latest_marked(reference, criteria)
      stream = @pg_stream_factory.call(reference)

      @client.read(
        stream,
        options: {
          direction: :desc,
          max_count: 1,
          filter: {
            event_types: [ { type: criteria.event_type, markers: [ criteria.marker ] } ]
          }
        }
      )
    rescue PgEventstore::StreamNotFoundError
      []
    end

    def read_global_marked(criteria)
      events = @client.read(
        PgEventstore::Stream.all_stream,
        options: {
          direction: criteria.direction,
          max_count: criteria.query_max_count,
          filter: {
            streams: [ { context: criteria.stream_context, stream_name: criteria.stream_name } ],
            event_types: criteria.event_types.map do |event_type|
              { type: event_type, markers: criteria.markers }
            end
          }
        }
      )
      return events if events.length <= criteria.maximum_count

      raise EventHistoryLimitExceeded,
            "Global marked event read exceeded #{criteria.maximum_count} relevant events for #{criteria.markers.inspect}"
    end

    def read_latest_global_marked(criteria)
      @client.read(
        PgEventstore::Stream.all_stream,
        options: {
          direction: :desc,
          max_count: 1,
          filter: {
            streams: [ { context: criteria.stream_context, stream_name: criteria.stream_name } ],
            event_types: criteria.event_types.map do |event_type|
              { type: event_type, markers: criteria.markers }
            end
          }
        }
      ).first
    end

    def read_global_marked_page(criteria)
      @client.read(
        PgEventstore::Stream.all_stream,
        options: {
          direction: criteria.direction,
          from_position: criteria.from_position,
          to_position: criteria.to_position,
          max_count: criteria.query_max_count,
          filter: {
            streams: [ { context: criteria.stream_context, stream_name: criteria.stream_name } ],
            event_types: [ { type: criteria.event_type, markers: criteria.markers } ]
          }
        }
      )
    end

    def read_stream_page(reference, criteria)
      @client.read(
        @pg_stream_factory.call(reference),
        options: {
          direction: criteria.direction,
          from_revision: criteria.from_revision,
          to_revision: criteria.to_revision,
          max_count: criteria.query_max_count,
          filter: { event_types: [ criteria.event_type ] }
        }
      )
    rescue PgEventstore::StreamNotFoundError
      []
    end

    def read_stream_marked_page(reference, criteria)
      @client.read(
        @pg_stream_factory.call(reference),
        options: {
          direction: criteria.direction,
          from_revision: criteria.from_revision,
          to_revision: criteria.to_revision,
          max_count: criteria.query_max_count,
          filter: {
            event_types: [ { type: criteria.event_type, markers: criteria.markers } ]
          }
        }
      )
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
