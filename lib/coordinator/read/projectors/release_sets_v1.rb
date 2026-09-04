# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class ReleaseSetsV1
      PROJECTION = ProjectionDefinition.new(name: "release-sets", version: 1)

      def initialize(
        contract: Contracts::ReleaseSetSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        preparation_loader:,
        release_sets: Repositories::ReleaseSets.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @preparation_loader = preparation_loader
        @release_sets = release_sets
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        unless event.stream.stream_id == payload.release_set_id
          raise InvalidProjectionSource, "Projection identity does not match its source stream"
        end

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity: ProjectionEventIdentity.from_event(event),
            processed_at: Time.now.utc
          )

          project(event:, payload:)
        end
        nil
      end

      private

      def project(event:, payload:)
        case payload
        when Coordinator::Write::Events::ReleaseSetCreatedV1,
             Coordinator::Write::Events::ReleaseSetMemberAddedV1
          true
        when Coordinator::Write::Events::ReleaseSetPreparedV2
          @release_sets.store(event:, preparation: @preparation_loader.call(payload.release_set_id))
        when Coordinator::Write::Events::RepositoryIntegrationRecordedV2
          @release_sets.record_integration(event:, integration: payload)
        when Coordinator::Write::Events::RepositoryIntegrationMergeLinkedV1
          @release_sets.link_integration(event:, link: payload)
        when Coordinator::Write::Events::ReleaseSetVerificationRecordedV2
          @release_sets.record_verification(event:, verification: payload)
        when Coordinator::Write::Events::ReleaseSetIntegrationLinkedV1
          @release_sets.link_verification_integration(event:, link: payload)
        when Coordinator::Write::Events::ReleaseSetActivatedV2
          @release_sets.record_activation(event:, activation: payload)
        when Coordinator::Write::Events::ReleaseSetCompensationRequestedV2
          @release_sets.record_compensation_request(event:, request: payload)
        when Coordinator::Write::Events::ReleaseSetSuccessfulIntegrationLinkedV1
          @release_sets.link_compensation_integration(event:, link: payload)
        when Coordinator::Write::Events::ReleaseSetOutcomeRecordedV1
          @release_sets.record_outcome(event:, outcome: payload)
        when Coordinator::Write::Events::ReleaseSetCompletedV2
          @release_sets.record_completion(event:, completion: payload)
        else
          raise UnknownProjectionEvent, payload.class.name
        end
      end

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end
