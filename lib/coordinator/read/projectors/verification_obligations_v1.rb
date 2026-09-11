# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class VerificationObligationsV1
      PROJECTION = ProjectionDefinition.new(name: "verification_obligations", version: 1)

      def initialize(
        definition_loader: nil,
        outcome_state_loader: nil,
        contract: Contracts::VerificationObligationSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        obligations: Repositories::VerificationObligations.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @definition_loader = definition_loader
        @outcome_state_loader = outcome_state_loader
        @schema_registry = schema_registry
        @obligations = obligations
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        verify_stream_identity!(event, payload)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: event.created_at
          )

          project(event, payload)
        end

        nil
      end

      private

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::VerificationObligationCreatedV1
          @obligations.store_creation(event:, obligation: payload)
        when Coordinator::Write::Events::VerificationObligationCreatedV2,
             Coordinator::Write::Events::VerificationObligationAddedToChangeSetV1,
             Coordinator::Write::Events::VerificationObligationSourceCandidateAssignedV1,
             Coordinator::Write::Events::VerificationObligationTargetCandidateAssignedV1
          loaded = @definition_loader&.call(payload.obligation_id)
          raise InvalidProjectionSource, "Verification obligation definition is unavailable" unless loaded

          @obligations.store_definition_v2(event:, loaded:)
        when Coordinator::Write::Events::VerificationObligationClaimedV1
          @obligations.store_claim(event:, claim: payload)
        when Coordinator::Write::Events::VerificationObligationClaimedV2
          @obligations.store_claim_v2(event:, claim: payload)
        when Coordinator::Write::Events::VerificationEvidenceSubmittedV1
          @obligations.store_evidence(event:, submission: payload)
        when Coordinator::Write::Events::VerificationEvidenceSubmittedV2
          @obligations.store_evidence_v2(event:, submission: payload)
        when Coordinator::Write::Events::VerificationObligationEvidenceSelectedV1
          @obligations.touch_from_event(event:, obligation_id: payload.obligation_id)
        when Coordinator::Write::Events::VerificationObligationSatisfiedV1,
             Coordinator::Write::Events::VerificationObligationFailedV1
          @obligations.store_outcome(event:, outcome: payload)
        when Coordinator::Write::Events::VerificationObligationSatisfiedV2,
             Coordinator::Write::Events::VerificationObligationFailedV2
          state = @outcome_state_loader&.call(
            payload.obligation_id,
            through_revision: event.stream_revision
          )
          raise InvalidProjectionSource, "Verification obligation outcome state is unavailable" unless state

          @obligations.store_outcome_v2(event:, outcome: payload, state:)
        when Coordinator::Write::Events::VerificationObligationWaivedV1,
             Coordinator::Write::Events::VerificationObligationInvalidatedV1
          @obligations.store_lifecycle(event:, transition: payload)
        when Coordinator::Write::Events::VerificationObligationWaivedV2,
             Coordinator::Write::Events::VerificationObligationInvalidatedV2
          @obligations.store_lifecycle_v2(event:, transition: payload)
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

      def verify_stream_identity!(event, payload)
        return if event.stream.stream_id == payload.obligation_id

        raise InvalidProjectionSource, "VerificationObligation identity does not match its source stream"
      end
    end
  end
end
