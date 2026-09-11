# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class MergeSnapshotsV1
      PROJECTION = ProjectionDefinition.new(name: "merge-snapshots", version: 1)

      def initialize(
        registration_loader:,
        registration_contract: Contracts::MergeSnapshotSourceEvent.new,
        verification_contract: Contracts::MergeSnapshotVerificationSourceEvent.new,
        authorization_contract: Contracts::MergeAuthorizationSourceEvent.new,
        observation_contract: Contracts::MergeObservationSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        snapshots: Repositories::MergeSnapshots.new,
        authorizations: Repositories::MergeAuthorizations.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @registration_contract = registration_contract
        @registration_loader = registration_loader
        @verification_contract = verification_contract
        @authorization_contract = authorization_contract
        @observation_contract = observation_contract
        @schema_registry = schema_registry
        @snapshots = snapshots
        @authorizations = authorizations
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        raise InvalidProjectionSource, "Projection identity does not match its source stream" unless valid_stream_identity?(event, payload)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity: ProjectionEventIdentity.from_event(event),
            processed_at: event.created_at
          )

          project(event, payload)
        end
        nil
      end

      private

      def load_payload(event)
        result = contract_for(event).call(
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


      def contract_for(event)
        return @registration_contract if event.type == "MergeSnapshotRegistered"
        return @authorization_contract if event.type.start_with?("MergeAuthorization")
        return @observation_contract if %w[MergeObserved MergeObservationAuthorizationLinked].include?(event.type)

        @verification_contract
      end

      def valid_stream_identity?(event, payload)
        stream_id =
          case payload
          when Coordinator::Write::Events::MergeAuthorizationGrantedV2,
               Coordinator::Write::Events::MergeAuthorizationDeniedV2
            payload.authorization_id
          when Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV2
            payload.verification_id
          else
            payload.merge_snapshot_id
          end
        event.stream.stream_id == stream_id
      end

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::MergeSnapshotRegisteredV2
          @snapshots.store(event:, snapshot: @registration_loader.call(event, registration: payload))
        when Coordinator::Write::Events::MergeSnapshotVerificationSubmittedV2
          @snapshots.record_submission(event:, submission: payload)
        when Coordinator::Write::Events::MergeSnapshotVerificationAssignedV1
          true
        when Coordinator::Write::Events::MergeSnapshotVerificationSelectedV1
          @snapshots.record_selection(event:, selection: payload)
        when Coordinator::Write::Events::MergeSnapshotVerifiedV2
          @snapshots.record_verified(event:, verified: payload)
        when Coordinator::Write::Events::MergeAuthorizationGrantedV2,
             Coordinator::Write::Events::MergeAuthorizationDeniedV2
          @authorizations.store(event:, decision: payload)
        when Coordinator::Write::Events::MergeObservedV2
          @snapshots.record_observation(event:, observation: payload)
        when Coordinator::Write::Events::MergeObservationAuthorizationLinkedV1
          @snapshots.link_observation_authorization(event:, link: payload)
        else
          raise UnknownProjectionEvent, payload.class.name
        end
      end
    end
  end
end
