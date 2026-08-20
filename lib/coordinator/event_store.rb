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

    def read_all(reference)
      stream = @pg_stream_factory.call(reference)

      @client.read_paginated(stream, options: { direction: :asc }).flat_map(&:itself)
    end

    def append(reference, events)
      stream = @pg_stream_factory.call(reference)

      @client.append_to_stream(stream, events)
    end
  end
end
