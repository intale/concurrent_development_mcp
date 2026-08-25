# frozen_string_literal: true

module Coordinator::Write
  module DependencySatisfactions
    class SourceLoader
      include Dry::Monads[:result]
      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        release_history_loader: ReleaseSets::HistoryLoader.new(event_store:),
        contract: Contracts::DependencySatisfactionSource.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @release_history_loader = release_history_loader
        @contract = contract
      end

      def call(command:, dependency:)
        reference = command.source_event
        physical = @event_store.read_at(stream_reference(reference), reference.stream_revision)
        return source_failure(command, :dependency_source_not_found, "Exact source event was not found") unless physical

        payload = @schema_registry.load(
          type: physical.type,
          schema_version: physical.metadata.fetch("schema_version"),
          data: physical.data
        )
        evidence = SourceEvidenceV1.new(
          event: physical,
          reference: event_reference(physical),
          payload:,
          producer_state: load_producer(dependency.producer_work_item_id),
          release_state: release_state(payload)
        )
        validation = @contract.call(evidence:, command:, dependency:)
        return Success(evidence) if validation.success?

        source_failure(
          command,
          :dependency_source_invalid,
          "Exact source event violates the dependency source contract",
          errors: validation.errors.to_h
        )
      rescue KeyError, Dry::Struct::Error, EventSchemaRegistry::UnknownSchema,
             EventSchemaRegistry::SchemaMismatch, InvalidReleaseSetHistory => error
        source_failure(
          command,
          :dependency_source_invalid,
          "Exact source event could not be reconstructed",
          error: error.message
        )
      end

      private

      def load_producer(work_item_id)
        events = @event_store.read(
          @stream_factory.work_item(work_item_id),
          EventQueries::WORK_ITEM_FOR_COMPLETION
        ).map { load_event(_1) }
        Domain::WorkItems::State.reduce(events)
      end

      def release_state(payload)
        return unless Contracts::DependencySatisfactionSource::RELEASE_SET_SOURCES.any? { payload.is_a?(_1) }

        @release_history_loader.call(payload.release_set_id)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_reference(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def source_failure(command, code, message, details = {})
        Failure(
          OutcomeError.new(
            code:,
            message:,
            details: {
              change_set_id: command.change_set_id,
              dependency_id: command.dependency_id,
              source_event_id: command.source_event.event_id
            }.merge(details)
          )
        )
      end
    end
  end
end
