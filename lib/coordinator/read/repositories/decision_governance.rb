# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DecisionGovernance
      def fetch(decision_id)
        record = Coordinator::Read::DecisionDefinition.find_by(decision_id:)
        record && build_decision(record)
      end

      def fetch_many(decision_ids)
        records = Coordinator::Read::DecisionDefinition.where(decision_id: decision_ids).index_by(&:decision_id)
        decision_ids.filter_map { records[_1] && build_decision(records.fetch(_1)) }
      end

      def page(query)
        relation = decisions_for_repository(query.repository_id)
        if query.topic_id
          relation = relation.where("definition #>> '{document,topic,topic_id}' = ?", query.topic_id)
        end
        relation = relation.where(policy_status: query.policy_status) if query.policy_status
        relation = relation.where("decision_id > ?", query.after_decision_id) if query.after_decision_id
        rows = relation.order(:decision_id).page(1).per(query.limit + 1).to_a
        has_more = rows.length > query.limit
        items = rows.first(query.limit).map { build_decision(_1) }

        DecisionPageV1.new(
          repository_id: query.repository_id,
          topic_id: query.topic_id,
          policy_status: query.policy_status,
          items:,
          next_decision_id: has_more ? items.last.decision_id : nil,
          has_more:
        )
      end

      def partition_observations(partitions)
        records = Coordinator::Read::DecisionPartitionHead.where(
          partition_id: partitions.map(&:partition_id)
        ).index_by(&:partition_id)

        partitions.map do |partition|
          partition_observation(partition, records[partition.partition_id])
        end
      end

      private

      def decisions_for_repository(repository_id)
        decision_ids = Coordinator::Read::DecisionRepositoryMembership.where(repository_id:)
          .select(:decision_id)
        Coordinator::Read::DecisionDefinition.where(
          decision_id: decision_ids
        )
      end

      def partition_observation(partition, record)
        return DecisionResolution::PartitionObservationV1.new(
          partition:,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        ) unless record

        DecisionResolution::PartitionObservationV1.new(
          partition:,
          partition_revision: record.partition_revision,
          event: Coordinator::Write::EventReference.new(symbolize(record.event)),
          active_decisions: record.active_decisions.map do |head|
            Coordinator::Write::Decisions::DecisionHeadV1.new(symbolize(head))
          end.sort_by { [ _1.decision_id.b, _1.event.event_id.b ] }
        )
      end

      def build_decision(record)
        activated = activated_evidence(record)
        corrected = corrected_evidence(record)
        DecisionViewV1.new(
          decision_id: record.decision_id,
          interpretation_id: record.interpretation_id,
          source_message_id: record.source_message_id,
          policy_status: record.policy_status,
          definition: Coordinator::Write::Decisions::DecisionDefinitionV1.new(symbolize(record.definition)),
          slot: optional_value(Coordinator::Write::Decisions::DecisionSlotV1, record.slot),
          partitions: record.partitions.map do |partition|
            Coordinator::Write::Decisions::DecisionPartitionV1.new(symbolize(partition))
          end,
          classifier: Coordinator::Write::Interpretations::ClassifierAttributionV1.new(
            symbolize(record.classifier)
          ),
          scope_provenance: Coordinator::Write::Interpretations::DecisionScopeProvenanceV1.new(
            symbolize(record.scope_provenance)
          ),
          source_event: Coordinator::Write::EventReference.new(symbolize(record.source_event)),
          proposal_event: Coordinator::Write::EventReference.new(symbolize(record.proposal_event)),
          acceptance_event: Coordinator::Write::EventReference.new(symbolize(record.acceptance_event)),
          rationale: optional_value(Coordinator::Write::Decisions::DecisionActivationRationaleV1, record.rationale),
          correction_rationale: optional_value(
            Coordinator::Write::Decisions::DecisionCorrectionRationaleV1,
            record.correction_rationale
          ),
          previous_definition_digest: record.previous_definition_digest,
          correction_count: record.correction_count,
          recorded: lifecycle_evidence(
            event: record.recorded_event,
            actor: record.recorded_actor,
            occurred_at: record.recorded_at_domain,
            persisted_at: record.recorded_at_store,
            causation_id: record.recorded_causation_id,
            correlation_id: record.recorded_correlation_id
          ),
          activated:,
          corrected:,
          current_head: corrected || activated
        )
      end

      def activated_evidence(record)
        return unless record.activated_event

        lifecycle_evidence(
          event: record.activated_event,
          actor: record.activated_actor,
          occurred_at: record.activated_at_domain,
          persisted_at: record.activated_at_store,
          causation_id: record.activated_causation_id,
          correlation_id: record.activated_correlation_id
        )
      end

      def corrected_evidence(record)
        return unless record.corrected_event

        lifecycle_evidence(
          event: record.corrected_event,
          actor: record.corrected_actor,
          occurred_at: record.corrected_at_domain,
          persisted_at: record.corrected_at_store,
          causation_id: record.corrected_causation_id,
          correlation_id: record.corrected_correlation_id
        )
      end

      def lifecycle_evidence(event:, actor:, occurred_at:, persisted_at:, causation_id:, correlation_id:)
        DecisionLifecycleEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(event)),
          actor: AttributedActorV1.new(symbolize(actor)),
          occurred_at: occurred_at.utc.iso8601(6),
          persisted_at: persisted_at.utc.iso8601(6),
          causation_id:,
          correlation_id:
        )
      end

      def optional_value(type, attributes)
        type.new(symbolize(attributes)) if attributes
      end

      def symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array
          value.map { symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
