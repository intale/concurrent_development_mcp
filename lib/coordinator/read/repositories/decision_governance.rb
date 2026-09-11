# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class DecisionGovernance
      include EventTimestamped

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

      def store_decision(event:, decision:)
        create_from_event(Coordinator::Read::DecisionDefinition, event:, attributes: {
          decision_id: decision.decision_id,
          interpretation_id: decision.interpretation_id,
          source_message_id: decision.source_message_id,
          policy_status: "recorded",
          definition_digest: decision.definition.digest,
          definition: decision.definition.to_h,
          slot: nil,
          partitions: [],
          classifier: decision.classifier.to_h,
          scope_provenance: decision.scope_provenance.to_h,
          source_event: decision.source_event.to_h,
          proposal_event: decision.proposal_event.to_h,
          acceptance_event: decision.acceptance_event.to_h,
          recorded_event: event_reference(event).to_h,
          activated_event: nil,
          rationale: nil,
          recorded_actor: actor(event).to_h,
          activated_actor: nil,
          recorded_markers: event.markers,
          activated_markers: nil,
          recorded_metadata: event.metadata,
          activated_metadata: nil,
          recorded_causation_id: event.causation_id,
          recorded_correlation_id: event.correlation_id,
          activated_causation_id: nil,
          activated_correlation_id: nil,
          recorded_at_domain: decision.recorded_at,
          activated_at_domain: nil,
          recorded_at_store: event.created_at,
          activated_at_store: nil
        })
      end

      def store_decision_v2(event:, decision:, interpretation:)
        definition = normalize_definition(decision.definition)
        create_from_event(Coordinator::Read::DecisionDefinition, event:, attributes: {
          decision_id: decision.decision_id,
          interpretation_id: decision.interpretation_id,
          source_message_id: decision.source_message_id,
          policy_status: "recorded",
          definition_digest: definition.digest,
          definition: definition.to_h,
          slot: nil,
          partitions: [],
          classifier: interpretation.classifier.to_h,
          scope_provenance: interpretation.scope_provenance.to_h,
          source_event: interpretation.source_event.to_h,
          proposal_event: interpretation.proposal_event.to_h,
          acceptance_event: interpretation.acceptance_event.to_h,
          recorded_event: event_reference(event).to_h,
          activated_event: nil,
          rationale: nil,
          recorded_actor: actor(event).to_h,
          activated_actor: nil,
          recorded_markers: event.markers,
          activated_markers: nil,
          recorded_metadata: event.metadata,
          activated_metadata: nil,
          recorded_causation_id: event.causation_id,
          recorded_correlation_id: event.correlation_id,
          activated_causation_id: nil,
          activated_correlation_id: nil,
          recorded_at_domain: event.created_at,
          activated_at_domain: nil,
          recorded_at_store: event.created_at,
          activated_at_store: nil
        })
      end

      def activate_decision(event:, activation:)
        record = Coordinator::Read::DecisionDefinition.find(activation.decision_id)
        save_from_event(record, event:, attributes: {
          policy_status: "active",
          slot: activation.slot&.to_h,
          partitions: activation.partitions.map(&:to_h),
          activated_event: event_reference(event).to_h,
          rationale: activation.rationale.to_h,
          activated_actor: actor(event).to_h,
          activated_markers: event.markers,
          activated_metadata: event.metadata,
          activated_causation_id: event.causation_id,
          activated_correlation_id: event.correlation_id,
          activated_at_domain: activation.activated_at,
          activated_at_store: event.created_at
        })
      end

      def activate_decision_v2(event:, activation:)
        record = Coordinator::Read::DecisionDefinition.find(activation.decision_id)
        definition = definition_from(record)
        save_from_event(record, event:, attributes: {
          policy_status: "active",
          partitions: partition_builder.call(definition).map(&:to_h),
          activated_event: event_reference(event).to_h,
          rationale: {
            code: "activated",
            summary: activation.rationale
          },
          activated_actor: actor(event).to_h,
          activated_markers: event.markers,
          activated_metadata: event.metadata,
          activated_causation_id: event.causation_id,
          activated_correlation_id: event.correlation_id,
          activated_at_domain: event.created_at,
          activated_at_store: event.created_at
        })
      end

      def correct_decision(event:, correction:)
        record = Coordinator::Read::DecisionDefinition.find(correction.decision_id)
        save_from_event(record, event:, attributes: {
          interpretation_id: correction.interpretation_id,
          source_message_id: correction.source_message_id,
          definition_digest: correction.definition.digest,
          definition: correction.definition.to_h,
          slot: correction.slot&.to_h,
          partitions: correction.partitions.map(&:to_h),
          classifier: correction.classifier.to_h,
          scope_provenance: correction.scope_provenance.to_h,
          source_event: correction.source_event.to_h,
          proposal_event: correction.proposal_event.to_h,
          acceptance_event: correction.acceptance_event.to_h,
          previous_definition_digest: correction.previous_definition_digest,
          correction_rationale: correction.rationale.to_h,
          corrected_event: event_reference(event).to_h,
          corrected_actor: actor(event).to_h,
          corrected_markers: event.markers,
          corrected_metadata: event.metadata,
          corrected_causation_id: event.causation_id,
          corrected_correlation_id: event.correlation_id,
          corrected_at_domain: correction.corrected_at,
          corrected_at_store: event.created_at,
          correction_count: record.correction_count + 1
        })
      end

      def correct_decision_v2(event:, correction:, interpretation:)
        record = Coordinator::Read::DecisionDefinition.find(correction.decision_id)
        previous_definition_digest = record.definition_digest
        definition = normalize_definition(correction.definition)
        generated_slot = slot_builder.call(definition)
        save_from_event(record, event:, attributes: {
          interpretation_id: correction.interpretation_id,
          source_message_id: correction.source_message_id,
          definition_digest: definition.digest,
          definition: definition.to_h,
          slot: generated_slot ? record.slot : nil,
          partitions: partition_builder.call(definition).map(&:to_h),
          classifier: interpretation.classifier.to_h,
          scope_provenance: interpretation.scope_provenance.to_h,
          source_event: interpretation.source_event.to_h,
          proposal_event: interpretation.proposal_event.to_h,
          acceptance_event: interpretation.acceptance_event.to_h,
          previous_definition_digest:,
          correction_rationale: {
            code: "corrected",
            summary: correction.rationale
          },
          corrected_event: event_reference(event).to_h,
          corrected_actor: actor(event).to_h,
          corrected_markers: event.markers,
          corrected_metadata: event.metadata,
          corrected_causation_id: event.causation_id,
          corrected_correlation_id: event.correlation_id,
          corrected_at_domain: event.created_at,
          corrected_at_store: event.created_at,
          correction_count: record.correction_count + 1
        })
      end

      def open_slot(event:, opening:)
        create_from_event(Coordinator::Read::DecisionSlotHead, event:, attributes: {
          slot_id: opening.slot.slot_id,
          decision_id: opening.opened_by.decision_id,
          slot: opening.slot.to_h,
          head: opening.opened_by.to_h,
          opened_event: event_reference(event).to_h,
          changed_event: nil,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          opened_at_domain: opening.opened_at,
          changed_at_domain: nil,
          event_created_at: event.created_at
        })
      end

      def open_slot_v2(event:, opening:)
        decision = Coordinator::Read::DecisionDefinition.find(opening.opened_by)
        generated = slot_builder.call(definition_from(decision))
        unless generated && generated.document == opening.slot
          raise InvalidProjectionSource, "Decision slot opening does not match its Decision definition"
        end

        slot = Coordinator::Write::Decisions::DecisionSlotV1.new(
          slot_id: opening.slot_id,
          document: opening.slot,
          compound_marker: generated.compound_marker
        )
        create_from_event(Coordinator::Read::DecisionSlotHead, event:, attributes: {
          slot_id: opening.slot_id,
          decision_id: opening.opened_by,
          slot: slot.to_h,
          head: nil,
          opened_event: event_reference(event).to_h,
          changed_event: nil,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          opened_at_domain: event.created_at,
          changed_at_domain: nil,
          event_created_at: event.created_at
        })
        save_from_event(decision, event:, attributes: { slot: slot.to_h }) unless newer?(decision, event)
      end

      def change_slot_head(event:, change:)
        record = Coordinator::Read::DecisionSlotHead.find(change.slot_id)
        save_from_event(record, event:, attributes: {
          decision_id: change.head&.decision_id,
          head: change.head&.to_h,
          changed_event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          changed_at_domain: change.changed_at,
          event_created_at: event.created_at
        })
      end

      def change_slot_head_v2(event:, change:)
        record = Coordinator::Read::DecisionSlotHead.find(change.slot_id)
        previous_decision_id = record.decision_id
        save_from_event(record, event:, attributes: {
          decision_id: change.head&.decision_id,
          head: change.head&.to_h,
          changed_event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          changed_at_domain: event.created_at,
          event_created_at: event.created_at
        })

        if previous_decision_id && previous_decision_id != change.head&.decision_id
          previous = Coordinator::Read::DecisionDefinition.find_by(decision_id: previous_decision_id)
          save_from_event(previous, event:, attributes: { slot: nil }) if previous && !newer?(previous, event)
        end
        return unless change.head

        decision = Coordinator::Read::DecisionDefinition.find(change.head.decision_id)
        save_from_event(decision, event:, attributes: { slot: record.slot }) unless newer?(decision, event)
      end

      def advance_partition(event:, advancement:)
        record = Coordinator::Read::DecisionPartitionHead.find_or_initialize_by(
          partition_id: advancement.partition.partition_id
        )
        return if record.persisted? && record.partition_revision >= advancement.partition_revision

        record.assign_attributes(
          decision_id: advancement.decision.decision_id,
          partition: advancement.partition.to_h,
          partition_revision: advancement.partition_revision,
          decision: advancement.decision.to_h,
          active_decisions: advancement.active_decisions.map(&:to_h),
          change_kind: advancement.change_kind,
          event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          advanced_at_domain: advancement.advanced_at,
          event_created_at: event.created_at
        )
        save_from_event(record, event:)
      end

      def apply_partition_delta(event:, delta:)
        record = Coordinator::Read::DecisionPartitionHead.find_or_initialize_by(
          partition_id: delta.partition_id
        )
        return record if record.persisted? && record.partition_revision >= delta.partition_revision

        decision_record = Coordinator::Read::DecisionDefinition.find(delta.decision_id)
        decision_head = current_head(decision_record)
        active = record.persisted? ? record.active_decisions.to_h { [ _1.fetch("decision_id"), _1 ] } : {}
        if delta.is_a?(Coordinator::Write::Events::DecisionAddedToPartitionV1)
          active[delta.decision_id] = decision_head.to_h
        else
          raise InvalidProjectionSource, "Decision partition removal precedes its addition" unless record.persisted?

          active.delete(delta.decision_id)
        end
        partition = if record.persisted?
                      Coordinator::Write::Decisions::DecisionPartitionV1.new(symbolize(record.partition))
        else
                      partition_builder.call(definition_from(decision_record)).find do
                        _1.partition_id == delta.partition_id
                      end
        end
        raise InvalidProjectionSource, "Decision partition cannot be reconstructed" unless partition

        save_from_event(record, event:, attributes: {
          decision_id: delta.decision_id,
          partition: partition.to_h,
          partition_revision: delta.partition_revision,
          decision: decision_head.to_h,
          active_decisions: active.values.sort_by { _1.fetch(:decision_id, _1["decision_id"]).b },
          change_kind: decision_head.event.type == "DecisionDefinitionCorrected" ? "corrected" : "activated",
          event: event_reference(event).to_h,
          actor: actor(event).to_h,
          markers: event.markers,
          metadata: event.metadata,
          causation_id: event.causation_id,
          correlation_id: event.correlation_id,
          advanced_at_domain: event.created_at,
          event_created_at: event.created_at
        })
      end

      private

      def normalize_definition(document)
        Coordinator::Write::Decisions::DecisionDefinitionV1.new(
          document:,
          digest: canonical_json.sha256(document.to_h)
        )
      end

      def definition_from(record)
        Coordinator::Write::Decisions::DecisionDefinitionV1.new(symbolize(record.definition))
      end

      def current_head(record)
        reference = record.corrected_event || record.activated_event
        raise InvalidProjectionSource, "Decision partition fact has no active Decision head" unless reference

        event = Coordinator::Write::EventReference.new(symbolize(reference))
        Coordinator::Write::Decisions::DecisionHeadV1.new(
          decision_id: record.decision_id,
          decision_revision: event.stream_revision,
          event:
        )
      end

      def newer?(record, event)
        record.updated_at && record.updated_at > event.created_at
      end

      def partition_builder
        @partition_builder ||= Coordinator::Write::Decisions::DecisionPartitionBuilder.new
      end

      def slot_builder
        @slot_builder ||= Coordinator::Write::Decisions::DecisionSlotBuilder.new
      end

      def canonical_json
        @canonical_json ||= Coordinator::Write::CanonicalJson.new
      end

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

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
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
