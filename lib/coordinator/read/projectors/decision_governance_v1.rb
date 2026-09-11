# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class DecisionGovernanceV1
      PROJECTION = ProjectionDefinition.new(name: "decision_governance", version: 1)

      def initialize(
        contract: Contracts::DecisionGovernanceSourceEvent.new,
        interpretation_evidence_loader:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        governance: Repositories::DecisionGovernance.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @interpretation_evidence_loader = interpretation_evidence_loader
        @schema_registry = schema_registry
        @governance = governance
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

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, payload)
        expected_id = case payload
        when Coordinator::Write::Events::DecisionRecordedV1,
             Coordinator::Write::Events::DecisionActivatedV1,
             Coordinator::Write::Events::DecisionDefinitionCorrectedV1,
             Coordinator::Write::Events::DecisionRecordedV2,
             Coordinator::Write::Events::DecisionActivatedV2,
             Coordinator::Write::Events::DecisionDefinitionCorrectedV2
          payload.decision_id
        when Coordinator::Write::Events::DecisionSlotOpenedV1
          payload.slot.slot_id
        when Coordinator::Write::Events::DecisionSlotHeadChangedV1
          payload.slot_id
        when Coordinator::Write::Events::DecisionPartitionAdvancedV1
          payload.partition.partition_id
        when Coordinator::Write::Events::DecisionSlotOpenedV2,
             Coordinator::Write::Events::DecisionSlotHeadChangedV2
          payload.slot_id
        when Coordinator::Write::Events::DecisionAddedToPartitionV1,
             Coordinator::Write::Events::DecisionRemovedFromPartitionV1
          payload.partition_id
        end
        return if event.stream.stream_id == expected_id

        raise InvalidProjectionSource, "Decision governance identity does not match its source stream"
      end

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::DecisionRecordedV1
          @governance.store_decision(event:, decision: payload)
        when Coordinator::Write::Events::DecisionActivatedV1
          @governance.activate_decision(event:, activation: payload)
        when Coordinator::Write::Events::DecisionDefinitionCorrectedV1
          @governance.correct_decision(event:, correction: payload)
        when Coordinator::Write::Events::DecisionSlotOpenedV1
          @governance.open_slot(event:, opening: payload)
        when Coordinator::Write::Events::DecisionSlotHeadChangedV1
          @governance.change_slot_head(event:, change: payload)
        when Coordinator::Write::Events::DecisionPartitionAdvancedV1
          @governance.advance_partition(event:, advancement: payload)
        when Coordinator::Write::Events::DecisionRecordedV2
          @governance.store_decision_v2(
            event:,
            decision: payload,
            interpretation: @interpretation_evidence_loader.call(payload.interpretation_id)
          )
        when Coordinator::Write::Events::DecisionActivatedV2
          @governance.activate_decision_v2(event:, activation: payload)
        when Coordinator::Write::Events::DecisionDefinitionCorrectedV2
          @governance.correct_decision_v2(
            event:,
            correction: payload,
            interpretation: @interpretation_evidence_loader.call(payload.interpretation_id)
          )
        when Coordinator::Write::Events::DecisionSlotOpenedV2
          @governance.open_slot_v2(event:, opening: payload)
        when Coordinator::Write::Events::DecisionSlotHeadChangedV2
          @governance.change_slot_head_v2(event:, change: payload)
        when Coordinator::Write::Events::DecisionAddedToPartitionV1,
             Coordinator::Write::Events::DecisionRemovedFromPartitionV1
          @governance.apply_partition_delta(event:, delta: payload)
        end
      end
    end
  end
end
