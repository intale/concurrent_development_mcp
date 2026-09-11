# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class CandidateImpactPolicies
      TOPIC_ID = "candidate.impact_policy"

      def fetch(change_set_id)
        partition_record = Coordinator::Read::DecisionPartitionHead.find_by(
          partition_id: "changeset:#{change_set_id}:candidate"
        )
        return unless partition_record

        head = Coordinator::Write::Decisions::DecisionHeadV1.new(symbolize(partition_record.decision))
        return unless active_head?(partition_record, head)

        decision_record = Coordinator::Read::DecisionDefinition.find_by(decision_id: head.decision_id)
        return unless coherent_head?(decision_record, head)

        definition = Coordinator::Write::Decisions::DecisionDefinitionV1.new(
          symbolize(decision_record.definition)
        )
        document = definition.document
        return unless coherent_policy?(document, change_set_id)

        CandidateImpactPolicySummaryV1.new(
          change_set_id:,
          partition: Coordinator::Write::Decisions::DecisionPartitionV1.new(
            symbolize(partition_record.partition)
          ),
          head:,
          definition_digest: definition.digest,
          required_evidence: document.value.items,
          enforcement: document.enforcement.level,
          valid_from: document.validity.valid_from || effective_from(decision_record, head),
          evidence: evidence(partition_record)
        )
      end

      private

      def active_head?(record, head)
        record.active_decisions.any? do |value|
          Coordinator::Write::Decisions::DecisionHeadV1.new(symbolize(value)) == head
        end
      end

      def coherent_head?(record, head)
        return false unless record

        persisted_reference = case head.event.type
        when "DecisionActivated" then record.activated_event
        when "DecisionDefinitionCorrected" then record.corrected_event
        end
        return false unless persisted_reference

        Coordinator::Write::EventReference.new(symbolize(persisted_reference)) == head.event &&
          record.definition_digest == head_definition_digest(record)
      end

      def head_definition_digest(record)
        Coordinator::Write::Decisions::DecisionDefinitionV1.new(
          symbolize(record.definition)
        ).digest
      end

      def coherent_policy?(document, change_set_id)
        document.topic.topic_id == TOPIC_ID &&
          document.scope.change_set_id == change_set_id &&
          document.value.schema == "string-set/v1" &&
          document.value.items
      end

      def effective_from(record, head)
        timestamp = if head.event.type == "DecisionDefinitionCorrected"
          record.corrected_at_domain
        else
          record.activated_at_domain
        end
        timestamp.utc.iso8601(6)
      end

      def evidence(record)
        CandidateImpactPolicyEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.event)),
          actor: AttributedActorV1.new(symbolize(record.actor)),
          markers: record.markers,
          metadata: record.metadata,
          occurred_at: record.advanced_at_domain.utc.iso8601(6),
          persisted_at: record.event_created_at.utc.iso8601(6),
          causation_id: record.causation_id,
          correlation_id: record.correlation_id
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
