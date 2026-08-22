# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class Correct
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, corrected_at:)
          return revision_changed(state.current, command) unless state.current.head.event == command.expected_head

          slot_error = validate_slots(state)
          return slot_error if slot_error

          Success(build_plan(state, command, corrected_at))
        end

        private

        def build_plan(state, command, corrected_at)
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
              event: correction_event(current, candidate, command, corrected_at)
            )
          ]
          writes.concat(slot_writes(state, correction_head, corrected_at))
          writes.concat(partition_writes(state.partition_states, correction_head, corrected_at))

          EventPlan.new(writes:)
        end

        def correction_event(current, candidate, command, corrected_at)
          proposal = candidate.proposal.proposal
          Events::DecisionDefinitionCorrectedV1.new(
            decision_id: command.decision_id,
            interpretation_id: command.interpretation_id,
            source_message_id: proposal.source_message_id,
            source_event: proposal.source_event,
            proposal_event: candidate.proposal.event,
            acceptance_event: candidate.acceptance.event,
            previous_head: current.head,
            previous_definition_digest: current.definition.digest,
            definition: candidate.definition,
            classifier: proposal.classifier,
            scope_provenance: proposal.scope_provenance,
            previous_slot: current.slot,
            slot: candidate.slot,
            previous_partitions: current.partitions,
            partitions: candidate.partitions,
            rationale: command.rationale,
            corrected_at:
          )
        end

        def slot_writes(state, correction_head, corrected_at)
          old_slot = state.current.slot
          new_slot = state.candidate.slot
          return [] unless old_slot || new_slot
          return advance_same_slot(old_slot, state.current.head, correction_head, corrected_at) if old_slot == new_slot

          writes = []
          writes << head_change(old_slot, state.current.head, nil, corrected_at) if old_slot
          return writes unless new_slot

          new_state = slot_state(state, new_slot)
          unless new_state.opened
            writes << EventWrite.new(
              stream: @stream_factory.decision_slot(new_slot.slot_id),
              event: Events::DecisionSlotOpenedV1.new(
                slot: new_slot,
                opened_by: correction_head,
                opened_at: corrected_at
              )
            )
          end
          writes << head_change(new_slot, nil, correction_head, corrected_at)
          writes
        end

        def advance_same_slot(slot, previous_head, head, corrected_at)
          return [] unless slot

          [ head_change(slot, previous_head, head, corrected_at) ]
        end

        def head_change(slot, previous_head, head, corrected_at)
          EventWrite.new(
            stream: @stream_factory.decision_slot(slot.slot_id),
            event: Events::DecisionSlotHeadChangedV1.new(
              slot_id: slot.slot_id,
              previous_head:,
              head:,
              changed_at: corrected_at
            )
          )
        end

        def partition_writes(states, correction_head, corrected_at)
          states.map do |state|
            next_revision = state.latest_revision ? state.latest_revision + 1 : 0
            EventWrite.new(
              stream: @stream_factory.decision_partition(state.partition.partition_id),
              event: Events::DecisionPartitionAdvancedV1.new(
                partition: state.partition,
                partition_revision: next_revision,
                decision: correction_head,
                change_kind: "corrected",
                advanced_at: corrected_at
              )
            )
          end
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
