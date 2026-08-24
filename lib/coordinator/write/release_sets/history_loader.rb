# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class HistoryLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(release_set_id)
        preparation = nil
        integrations = []
        verifications = []
        activation = nil
        compensation_request = nil
        completion = nil
        events = @event_store.read(
          @stream_factory.release_set(release_set_id),
          EventQueries::RELEASE_SET_LIFECYCLE
        )
        events.each do |event|
          payload = load_event(event)
          validate_identity!(payload, release_set_id:, event:)
          case payload
          when Events::ReleaseSetPreparedV1
            raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate preparation facts" if preparation

            preparation = PreparationFactV1.new(
              payload:,
              event: event_reference(event),
              correlation_id: event.correlation_id
            )
          when Events::RepositoryIntegrationRecordedV1
            integrations << IntegrationFactV1.new(payload:, event: event_reference(event))
          when Events::ReleaseSetVerificationRecordedV1
            verifications << VerificationFactV1.new(payload:, event: event_reference(event))
          when Events::ReleaseSetActivatedV1
            raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate activation facts" if activation

            activation = ActivationFactV1.new(payload:, event: event_reference(event))
          when Events::ReleaseSetCompensationRequestedV1
            if compensation_request
              raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate compensation requests"
            end

            compensation_request = CompensationRequestFactV1.new(payload:, event: event_reference(event))
          when Events::ReleaseSetCompletedV1
            raise InvalidReleaseSetHistory, "ReleaseSet contains duplicate completion facts" if completion

            completion = CompletionFactV1.new(payload:, event: event_reference(event))
          end
        end
        Domain::ReleaseSets::LifecycleStateV1.new(
          preparation:,
          integrations: integrations.freeze,
          verifications: verifications.freeze,
          activation:,
          compensation_request:,
          completion:
        )
      rescue Dry::Struct::Error => error
        raise InvalidReleaseSetHistory, error.message
      end

      private

      def validate_identity!(payload, release_set_id:, event:)
        return if payload.release_set_id == release_set_id && event.stream.stream_id == release_set_id

        raise InvalidReleaseSetHistory, "ReleaseSet event identity does not match its stream"
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
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
    end
  end
end
