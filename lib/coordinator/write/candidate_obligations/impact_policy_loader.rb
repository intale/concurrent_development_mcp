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
        canonical_json: CanonicalJson.new,
        definition_contract: Contracts::CandidateImpactPolicyDefinition.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @definition_loader = definition_loader
        @stream_factory = stream_factory
        @canonical_json = canonical_json
        @definition_contract = definition_contract
      end

      def call(policy_partition_event:, policy_head:, change_set_id:, observed_at:)
        persisted_partition = @exact_loader.call(policy_partition_event)
        partition_event = payload!(persisted_partition, Events::DecisionPartitionAdvancedV1)
        partition = expected_partition(change_set_id)
        validate_partition!(persisted_partition.reference, partition_event, partition)
        definition = @definition_loader.call(head: policy_head, partition:)
        validate_definition!(definition, change_set_id)

        current = current_partition_event(partition.partition_id)
        return PolicyObservationV1.stale unless current == persisted_partition.reference
        return PolicyObservationV1.stale unless partition_event.active_decisions.include?(policy_head)

        level = definition.document.enforcement.level
        return PolicyObservationV1.non_gating unless GATE_LEVELS.include?(level)

        valid_from = definition.document.validity.valid_from
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

      def current_partition_event(partition_id)
        event = @event_store.read_grouped(
          @stream_factory.decision_partition(partition_id),
          EventQueries::DECISION_PARTITION_LATEST
        ).first
        return unless event

        event_reference(event)
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
        heads = payload.active_decisions
        valid = reference.type == "DecisionPartitionAdvanced" &&
                reference.stream_context == "HumanGuidance" &&
                reference.stream_name == "DecisionPartition" &&
                reference.stream_id == expected.partition_id &&
                payload.partition == expected &&
                payload.partition_revision == reference.stream_revision &&
                heads == heads.uniq(&:decision_id).sort_by { _1.decision_id.b } &&
                heads.include?(payload.decision)
        return if valid

        invalid!(
          "candidate_impact_policy_partition_invalid",
          partition_event: reference.to_h,
          expected_partition: expected.to_h
        )
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
