# frozen_string_literal: true

module Coordinator::Processes
  class WorkIntentionExpirySourceLoader
    def initialize(
      event_store:,
      source_builder: WorkIntentionExpirySourceBuilder.new,
      stream_factory: Coordinator::Write::StreamFactory.new,
      reloaded_source_contract: Contracts::ReloadedWorkIntentionExpirySource.new
    )
      @event_store = event_store
      @source_builder = source_builder
      @stream_factory = stream_factory
      @reloaded_source_contract = reloaded_source_contract
    end

    def call(locator)
      event = @event_store.read_at(
        @stream_factory.resource_work_intention(locator.resource_stream_id),
        locator.stream_revision
      )
      raise InvalidSourceEvent, "scheduled work-intention expiry source event is unavailable" unless event

      source = @source_builder.call(event)
      loaded = Coordinator::Write::WorkIntentionLoader.new(event_store: @event_store).call(
        locator.resource_stream_id
      )
      source = WorkIntentionExpirySource.new(source.attributes.merge(state: loaded.state))
      result = @reloaded_source_contract.call(locator:, source:)
      raise InvalidSourceEvent, result.errors.to_h.inspect if result.failure?

      source
    end
  end
end
