# frozen_string_literal: true

class FakeEventStore
  attr_reader :attempted_event_ids, :multiple_calls

  def initialize(retry_once: false)
    @attempted_event_ids = []
    @multiple_calls = 0
    @retry_once = retry_once
    @streams = Hash.new { |hash, key| hash[key] = [] }
  end

  def multiple
    @multiple_calls += 1

    if @retry_once
      snapshot = duplicate_streams
      yield
      @streams = snapshot
      @retry_once = false
    end

    snapshot = duplicate_streams
    yield
  rescue StandardError
    @streams = snapshot if snapshot
    raise
  end

  def read_all(reference)
    @streams.fetch(reference.to_h, []).map(&:dup)
  end

  def append(reference, events_or_event)
    events = events_or_event.is_a?(Array) ? events_or_event : [ events_or_event ]
    persisted = events.map do |event|
      event.dup.tap do |copy|
        copy.stream = PgEventstore::Stream.new(**reference.to_h)
        copy.stream_revision = @streams[reference.to_h].length
        @streams[reference.to_h] << copy
        @attempted_event_ids << copy.id
      end
    end

    events_or_event.is_a?(Array) ? persisted : persisted.first
  end

  def stream_events(reference)
    read_all(reference)
  end

  private

  def duplicate_streams
    @streams.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(key, events), copy|
      copy[key.dup] = events.map(&:dup)
    end
  end
end
