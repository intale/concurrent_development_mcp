# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ImpactPolicyLoader
      GATE_LEVELS = %w[verification_gate merge_gate].freeze

      def initialize(
        event_store:,
        exact_loader: ExactEventLoader.new(event_store:),
        definition_loader: DecisionDefinitionLoader.new(event_store:, exact_loader:),
        stream_factory: StreamFactory.new,
        partition_state_loader: Decisions::PartitionStateLoader.new(event_store:),
        canonical_json: CanonicalJson.new,
        definition_contract: Contracts::CandidateImpactPolicyDefinition.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @definition_loader = definition_loader
        @stream_factory = stream_factory
        @partition_state_loader = partition_state_loader
        @canonical_json = canonical_json
        @definition_contract = definition_contract
      end

      def call(policy_partition_event:, policy_head:, change_set_id:, observed_at:)
        persisted_partition = @exact_loader.call(policy_partition_event)
        partition = expected_partition(change_set_id)
        validate_partition!(persisted_partition.reference, persisted_partition.payload, partition)
        definition = @definition_loader.call(head: policy_head, partition:)
        validate_definition!(definition, change_set_id)

        state = @partition_state_loader.call(partition)
        return PolicyObservationV1.stale unless state.latest_event == persisted_partition.reference
        return PolicyObservationV1.stale unless state.active_decisions.include?(policy_head)

        level = definition.document.enforcement.level
        return PolicyObservationV1.non_gating unless GATE_LEVELS.include?(level)

        valid_from = definition.document.validity.valid_from || policy_head_created_at(policy_head)
        return PolicyObservationV1.inactive if valid_from > observed_at

        PolicyObservationV1.gating(
          ImpactPolicyEvidenceV1.new(
            partition_event: persisted_partition.reference,
            partition:,
            head: policy_head,
            definition_digest: definition.digest,
            change_set_id:,
            required_evidence: definition.document.value.items,
            enforcement: level,
            valid_from:
          )
        )
      end

      private

      def policy_head_created_at(policy_head)
        @exact_loader.call(policy_head.event).event.created_at.utc.iso8601(6)
      end

      def expected_partition(change_set_id)
        Decisions::DecisionPartitionV1.new(
          partition_id: "changeset:#{change_set_id}:candidate",
          topic_root: "candidate",
          anchor_kind: "changeset",
          anchor_id: change_set_id
        )
      end

      def validate_partition!(reference, payload, expected)
        valid = reference.stream_context == "HumanGuidance" &&
                reference.stream_name == "DecisionPartition" &&
                reference.stream_id == expected.partition_id &&
                partition_payload_valid?(payload, expected, reference)
        return if valid

        invalid!(
          "candidate_impact_policy_partition_invalid",
          partition_event: reference.to_h,
          expected_partition: expected.to_h
        )
      end

      def partition_payload_valid?(payload, expected, reference)
        case payload
        when Events::DecisionAddedToPartitionV1, Events::DecisionRemovedFromPartitionV1
          payload.partition_id == expected.partition_id &&
            payload.partition_revision == reference.stream_revision
        else
          false
        end
      end

      def validate_definition!(definition, change_set_id)
        canonical_digest = @canonical_json.sha256(definition.document.to_h)
        result = @definition_contract.call(
          definition:,
          change_set_id:,
          expected_digest: canonical_digest
        )
        return if result.success?

        invalid!(
          "candidate_impact_policy_definition_invalid",
          definition_digest: definition.digest,
          errors: result.errors.to_h
        )
      end

      def payload!(persisted, expected_class)
        return persisted.payload if persisted.payload.is_a?(expected_class)

        invalid!(
          "referenced_event_type_invalid",
          reference: persisted.reference.to_h,
          expected_class: expected_class.name,
          actual_class: persisted.payload.class.name
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

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
