# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ImpactPolicyLoader
      GATE_LEVELS = %w[verification_gate merge_gate].freeze

      def initialize(
        event_store:,
        exact_loader: ExactEventLoader.new(event_store:),
        stream_factory: StreamFactory.new,
        canonical_json: CanonicalJson.new,
        definition_contract: Contracts::CandidateImpactPolicyDefinition.new
      )
        @event_store = event_store
        @exact_loader = exact_loader
        @stream_factory = stream_factory
        @canonical_json = canonical_json
        @definition_contract = definition_contract
      end

      def call(command:, change_set_id:, observed_at:)
        persisted_partition = @exact_loader.call(command.policy_partition_event)
        partition_event = payload!(persisted_partition, Events::DecisionPartitionAdvancedV1)
        partition = expected_partition(change_set_id)
        validate_partition!(persisted_partition.reference, partition_event, partition)
        definition = load_definition(command.policy_head, partition)
        validate_definition!(definition, change_set_id)

        current = current_partition_event(partition.partition_id)
        return PolicyObservationV1.stale unless current == persisted_partition.reference
        return PolicyObservationV1.stale unless partition_event.active_decisions.include?(command.policy_head)

        level = definition.document.enforcement.level
        return PolicyObservationV1.non_gating unless GATE_LEVELS.include?(level)

        valid_from = definition.document.validity.valid_from
        return PolicyObservationV1.inactive if valid_from > observed_at

        PolicyObservationV1.gating(
          ImpactPolicyEvidenceV1.new(
            partition_event: persisted_partition.reference,
            partition:,
            head: command.policy_head,
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

      def load_definition(head, partition)
        validate_head_reference!(head)
        persisted = @exact_loader.call(head.event)
        case persisted.payload
        when Events::DecisionActivatedV1
          definition_from_activation(head, persisted.payload, partition)
        when Events::DecisionDefinitionCorrectedV1
          definition_from_correction(head, persisted.payload, partition)
        else
          invalid!("candidate_impact_policy_head_type_invalid", decision_head: head.to_h)
        end
      end

      def validate_head_reference!(head)
        reference = head.event
        valid = head.decision_revision == reference.stream_revision &&
                reference.stream_context == "HumanGuidance" &&
                reference.stream_name == "Decision" &&
                reference.stream_id == head.decision_id &&
                %w[DecisionActivated DecisionDefinitionCorrected].include?(reference.type)
        return if valid

        invalid!("candidate_impact_policy_head_invalid", decision_head: head.to_h)
      end

      def definition_from_activation(head, activation, partition)
        recorded = @exact_loader.call(activation.recorded_event)
        definition_event = payload!(recorded, Events::DecisionRecordedV1)
        valid = activation.decision_id == head.decision_id &&
                activation.partitions.include?(partition) &&
                definition_event.decision_id == head.decision_id &&
                definition_event.definition.digest == activation.definition_digest &&
                recorded.reference.stream_context == "HumanGuidance" &&
                recorded.reference.stream_name == "Decision" &&
                recorded.reference.stream_id == head.decision_id
        return definition_event.definition if valid

        invalid!("candidate_impact_policy_activation_invalid", decision_head: head.to_h)
      end

      def definition_from_correction(head, correction, partition)
        valid = correction.decision_id == head.decision_id &&
                correction.previous_head.decision_id == head.decision_id &&
                correction.previous_head.decision_revision < head.decision_revision &&
                correction.partitions.include?(partition)
        return correction.definition if valid

        invalid!("candidate_impact_policy_correction_invalid", decision_head: head.to_h)
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
