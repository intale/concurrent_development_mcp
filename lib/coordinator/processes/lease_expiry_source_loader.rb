# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpirySourceLoader
    def initialize(
      event_store:,
      source_builder: LeaseExpirySourceBuilder.new,
      stream_factory: Coordinator::Write::StreamFactory.new,
      reloaded_source_contract: Contracts::ReloadedLeaseExpirySource.new
    )
      @event_store = event_store
      @source_builder = source_builder
      @stream_factory = stream_factory
      @reloaded_source_contract = reloaded_source_contract
    end

    def call(locator)
      event = @event_store.read_at(
        @stream_factory.resource_lease(locator.resource_key_hash),
        locator.stream_revision
      )
      raise InvalidSourceEvent, "scheduled lease-expiry source event is unavailable" unless event

      source = @source_builder.call(event)
      result = @reloaded_source_contract.call(locator:, source:)
      raise InvalidSourceEvent, result.errors.to_h.inspect if result.failure?

      source
    end
  end
end
