# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class CurrentPartitionLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        source_builder: SourceBuilder.new(event_store:)
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @source_builder = source_builder
      end

      def call(change_set_id)
        event = @event_store.read_grouped(
          @stream_factory.decision_partition("changeset:#{change_set_id}:candidate"),
          Coordinator::Write::EventQueries::DECISION_PARTITION_LATEST
        ).first
        return unless event

        @source_builder.call(event)
      end
    end
  end
end
