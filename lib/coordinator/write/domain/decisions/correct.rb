# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class Correct
        include Dry::Monads[:result]

        MAXIMUM_ACTIVE_DECISIONS = 32

        def initialize(
          stream_factory: StreamFactory.new,
          maximum_active_decisions: MAXIMUM_ACTIVE_DECISIONS
        )
          @stream_factory = stream_factory
          @maximum_active_decisions = maximum_active_decisions
        end

        def call(state:, command:, corrected_at:)
          return revision_changed(state.current, command) unless state.current.head.event == command.expected_head

          slot_error = validate_slots(state)
          return slot_error if slot_error
          partition_error = validate_partitions(state, command)
          return partition_error if partition_error

          Success(build_plan(state, command))
        end

        private

        def build_plan(state, command)
          current = state.current
          candidate = state.candidate
          correction_head = Coordinator::Write::Decisions::DecisionHeadV1.new(
            decision_id: command.decision_id,
            decision_revision: candidate.correction_event.stream_revision,
            event: candidate.correction_event
          )
          writes = [
            EventWrite.new(
              stream: @stream_factory.decision(command.decision_id),
              event: Events::DecisionDerivedFromInterpretationV1.new(
                decision_id: command.decision_id,
                interpretation_id: command.interpretation_id
              )
            ),
            EventWrite.new(
              stream: @stream_factory.decision(command.decision_id),
              event: correction_event(candidate, command)
            )
          ]
          writes.concat(slot_writes(state, correction_head))
          writes.concat(
            partition_writes(
              state.partition_states,
              correction_head,
              candidate.partitions.map(&:partition_id)
            )
          )

          EventPlan.new(writes:)
        end

        def correction_event(candidate, command)
          proposal = candidate.proposal.proposal
          Events::DecisionDefinitionCorrectedV2.new(
            decision_id: command.decision_id,
            interpretation_id: command.interpretation_id,
            source_message_id: proposal.source_message_id,
            definition: candidate.definition.document,
            rationale: command.rationale.summary
          )
        end

        def slot_writes(state, correction_head)
          old_slot = state.current.slot
          new_slot = state.candidate.slot
          return [] unless old_slot || new_slot
          return advance_same_slot(old_slot, correction_head) if old_slot == new_slot

          writes = []
          writes << head_change(old_slot, nil) if old_slot
          return writes unless new_slot

          new_state = slot_state(state, new_slot)
          unless new_state.opened
            writes << EventWrite.new(
              stream: @stream_factory.decision_slot(new_slot.slot_id),
              event: Events::DecisionSlotOpenedV2.new(
                slot_id: new_slot.slot_id,
                slot: new_slot.document,
                opened_by: correction_head.decision_id
              )
            )
          end
          writes << head_change(new_slot, correction_head)
          writes
        end

        def advance_same_slot(slot, head)
          return [] unless slot

          [ head_change(slot, head) ]
        end

        def head_change(slot, head)
          EventWrite.new(
            stream: @stream_factory.decision_slot(slot.slot_id),
            event: Events::DecisionSlotHeadChangedV2.new(
              slot_id: slot.slot_id,
              head:
            )
          )
        end

        def partition_writes(states, correction_head, corrected_partition_ids)
          states.filter_map do |state|
            currently_present = state.active_decisions.any? { _1.decision_id == correction_head.decision_id }
            should_be_present = corrected_partition_ids.include?(state.partition.partition_id)
            next if currently_present == should_be_present

            next_revision = state.latest_revision ? state.latest_revision + 1 : 0
            EventWrite.new(
              stream: @stream_factory.decision_partition(state.partition.partition_id),
              event: (should_be_present ? Events::DecisionAddedToPartitionV1 : Events::DecisionRemovedFromPartitionV1).new(
                partition_id: state.partition.partition_id,
                partition_revision: next_revision,
                decision_id: correction_head.decision_id
              )
            )
          end
        end

        def validate_partitions(state, command)
          corrected_partition_ids = state.candidate.partitions.map(&:partition_id)
          invalid = state.current.partitions.filter_map do |partition|
            partition_state = state.partition_states.find do |candidate|
              candidate.partition.partition_id == partition.partition_id
            end
            observed = partition_state.active_decisions.find do |head|
              head.decision_id == command.decision_id
            end
            [ partition_state, observed ] unless observed == state.current.head
          end.first
          return invalid_partition(command, state.current.head, *invalid) if invalid

          full = state.partition_states.find do |partition_state|
            corrected_partition_ids.include?(partition_state.partition.partition_id) &&
              partition_state.active_decisions.none? { _1.decision_id == command.decision_id } &&
              partition_state.active_decisions.length >= @maximum_active_decisions
          end
          return partition_capacity(full) if full

          nil
        end

        def invalid_partition(command, expected, partition_state, observed)
          Failure(
            OutcomeError.new(
              code: :decision_partition_state_invalid,
              message: "DecisionPartition does not contain the exact current Decision head",
              details: {
                partition_id: partition_state.partition.partition_id,
                decision_id: command.decision_id,
                expected_head: expected.to_h,
                observed_head: observed&.to_h
              }
            )
          )
        end

        def partition_capacity(partition_state)
          Failure(
            OutcomeError.new(
              code: :decision_partition_capacity_reached,
              message: "Corrected DecisionPartition already contains the maximum active Decision heads",
              details: {
                partition_id: partition_state.partition.partition_id,
                active_decision_count: partition_state.active_decisions.length,
                maximum_active_decisions: @maximum_active_decisions
              }
            )
          )
        end

        def validate_slots(state)
          current_slot = state.current.slot
          if current_slot
            old_state = slot_state(state, current_slot)
            return invalid_slot(current_slot, old_state.head) unless old_state.opened && old_state.head == state.current.head
          end

          corrected_slot = state.candidate.slot
          return unless corrected_slot && corrected_slot != current_slot

          new_state = slot_state(state, corrected_slot)
          occupied_slot(corrected_slot, new_state.head) if new_state.head
        end

        def slot_state(state, slot)
          state.slot_states.find { _1.slot.slot_id == slot.slot_id }
        end

        def revision_changed(current, command)
          Failure(
            OutcomeError.new(
              code: :decision_revision_changed,
              message: "Decision has a different authoritative lifecycle head",
              details: {
                decision_id: command.decision_id,
                expected_head: command.expected_head.to_h,
                current_head: current.head.event.to_h
              }
            )
          )
        end

        def invalid_slot(slot, head)
          Failure(
            OutcomeError.new(
              code: :decision_slot_state_invalid,
              message: "Decision's authoritative slot does not match its lifecycle head",
              details: { slot_id: slot.slot_id, head: head&.to_h }
            )
          )
        end

        def occupied_slot(slot, head)
          Failure(
            OutcomeError.new(
              code: :decision_slot_occupied,
              message: "Corrected exclusive Decision slot already has an active head",
              details: {
                slot_id: slot.slot_id,
                decision_id: head.decision_id,
                event_id: head.event.event_id
              }
            )
          )
        end
      end
    end
  end
end
