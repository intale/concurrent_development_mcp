# frozen_string_literal: true

module Coordinator::Read::Projections
  class DecisionGovernance
    def initialize(definitions:, slots:, partitions:, slot_states: {}, partition_states: {},
      slot_builder: DecisionSlots.new, partition_builder: DecisionPartitions.new)
      @definitions, @slots, @partitions = definitions, slots, partitions
      @slot_states, @partition_states, @slot_builder, @partition_builder = slot_states, partition_states, slot_builder, partition_builder
    end

    def apply(event, source: {})
      data = Coordinator::Read::CommandResults::Source.document(event.data)
      case event.type
      when "DecisionRecorded" then record(event, data, source)
      when "DecisionActivated"
        attributes = { decision_id: data.fetch(:decision_id), policy_status: "active",
          partitions: @partition_builder.call(source.fetch(:definition).fetch(:document)),
          rationale: { code: "activated", summary: data.fetch(:rationale) } }.merge(lifecycle(event, :activated))
        @definitions.assign(attributes)
        @definitions.touch(attributes.slice(:decision_id), time: event.created_at)
      when "DecisionDefinitionCorrected" then correct(event, data, source)
      when "DecisionCorrectionsNumberChanged"
        @definitions.assign(decision_id: data.fetch(:decision_id), correction_count: data.fetch(:corrections_number))
        @definitions.touch({ decision_id: data.fetch(:decision_id) }, time: event.created_at)
      when "DecisionSlotOpened" then open_slot(event, data)
      when "DecisionSlotHeadChanged" then slot_head(event, data)
      when "DecisionAddedToPartition", "DecisionRemovedFromPartition" then partition_delta(event, data, source)
      end
      nil
    end

    private

    def record(event, data, source)
      attributes = data.slice(:decision_id, :interpretation_id, :source_message_id).merge(
        definition: source.fetch(:definition), definition_digest: source.fetch(:definition).fetch(:digest))
        .merge(source.fetch(:interpretation)).merge(lifecycle(event, :recorded))
      @definitions.insert(attributes.merge(policy_status: "recorded", slot: nil, partitions: [], correction_count: 0,
        created_at: event.created_at, updated_at: event.created_at))
      @definitions.assign(attributes)
      @definitions.touch(attributes.slice(:decision_id), time: event.created_at)
    end

    def correct(event, data, source)
      definition = source.fetch(:definition)
      attributes = data.slice(:decision_id, :interpretation_id, :source_message_id).merge(definition:,
        definition_digest: definition.fetch(:digest), previous_definition_digest: source.fetch(:previous_definition_digest),
        partitions: @partition_builder.call(definition.fetch(:document)),
        correction_rationale: { code: "corrected", summary: data.fetch(:rationale) })
        .merge(source.fetch(:interpretation)).merge(lifecycle(event, :corrected))
      attributes[:slot] = nil unless %w[single_choice manual_resolution].include?(definition.fetch(:document).fetch(:topic).fetch(:resolution_strategy))
      @definitions.assign(attributes)
      @definitions.touch(attributes.slice(:decision_id), time: event.created_at)
    end

    def open_slot(event, data)
      id = data.fetch(:slot_id)
      slot = @slot_builder.call(id, data.fetch(:slot))
      attributes = { slot_id: id, slot:, opened_event: Source.reference(event), opened_at_domain: event.created_at }
        .merge(envelope(event))
      @slots.insert(attributes.merge(decision_id: nil, head: nil, changed_event: nil, changed_at_domain: nil,
        created_at: event.created_at, updated_at: event.created_at))
      @slots.assign(attributes)
      @slots.touch({ slot_id: id }, time: event.created_at)
      (@slot_states[id] ||= { decision_id: nil })[:slot] = slot
      nil
    end

    def slot_head(event, data)
      id, head = data.values_at(:slot_id, :head)
      state = @slot_states.fetch(id)
      previous = state[:decision_id]
      target = head&.fetch(:decision_id)
      attributes = { slot_id: id, decision_id: target, head:, changed_event: Source.reference(event), changed_at_domain: event.created_at }
        .merge(envelope(event))
      @slots.assign(attributes)
      @slots.touch({ slot_id: id }, time: event.created_at)
      if previous && previous != target
        @definitions.assign(decision_id: previous, slot: nil)
        @definitions.touch({ decision_id: previous }, time: event.created_at)
      end
      if target
        @definitions.assign(decision_id: target, slot: state.fetch(:slot))
        @definitions.touch({ decision_id: target }, time: event.created_at)
      end
      state[:decision_id] = target
      nil
    end

    def partition_delta(event, data, source)
      id = data.fetch(:partition_id)
      active = (@partition_states[id] ||= {}).dup
      decision_id = data.fetch(:decision_id)
      event.type == "DecisionAddedToPartition" ? active[decision_id] = source.fetch(:head) : active.delete(decision_id)
      @partition_states[id] = active
      components = id.split(":")
      partition = { partition_id: id, anchor_kind: components.first, anchor_id: components[1...-1].join(":"), topic_root: components.last }
      attributes = data.slice(:partition_id, :partition_revision, :decision_id).merge(partition:, decision: source.fetch(:head),
        active_decisions: active.values.sort_by { _1.fetch(:decision_id).b }, change_kind: source.fetch(:change_kind),
        event: Source.reference(event), advanced_at_domain: event.created_at).merge(envelope(event))
      @partitions.insert(attributes.merge(created_at: event.created_at, updated_at: event.created_at))
      @partitions.assign(attributes)
      @partitions.touch({ partition_id: id }, time: event.created_at)
    end

    def lifecycle(event, prefix)
      Source.evidence(event, prefix:).except(:"#{prefix}_global_position")
    end

    def envelope(event)
      { actor: Source.actor(event), markers: event.markers, metadata: event.metadata,
        causation_id: event.causation_id, correlation_id: event.correlation_id, event_created_at: event.created_at }
    end
  end
end
