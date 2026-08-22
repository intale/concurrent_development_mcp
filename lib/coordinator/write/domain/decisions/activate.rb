# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Decisions
      class Activate
        include Dry::Monads[:result]

        MAXIMUM_ACTIVE_DECISIONS = 32

        def initialize(
          stream_factory: StreamFactory.new,
          maximum_active_decisions: MAXIMUM_ACTIVE_DECISIONS
        )
          @stream_factory = stream_factory
          @maximum_active_decisions = maximum_active_decisions
        end

        def call(state:, command:, activated_at:)
          return decision_exists(state.existing_decision, command) if state.existing_decision
          return interpretation_used(state.existing_activation) if state.existing_activation
          return slot_occupied(state.slot_head, state.candidate.slot) if state.slot_head
          capacity_error = partition_capacity_error(state, command)
          return capacity_error if capacity_error

          Success(build_plan(state, command, activated_at))
        end

        private

        def build_plan(state, command, activated_at)
          candidate = state.candidate
          decision_head = Coordinator::Write::Decisions::DecisionHeadV1.new(
            decision_id: command.decision_id,
            decision_revision: candidate.activated_event.stream_revision,
            event: candidate.activated_event
          )
          decision_stream = @stream_factory.decision(command.decision_id)
          writes = [
            EventWrite.new(
              stream: decision_stream,
              event: recorded_event(candidate, command, activated_at)
            ),
            EventWrite.new(
              stream: decision_stream,
              event: activated_event(candidate, command, activated_at)
            )
          ]
          writes.concat(slot_writes(candidate.slot, decision_head, activated_at))
          writes.concat(partition_writes(state.partition_states, decision_head, activated_at))

          EventPlan.new(writes:)
        end

        def recorded_event(candidate, command, activated_at)
          proposal = candidate.proposal.proposal
          Events::DecisionRecordedV1.new(
            decision_id: command.decision_id,
            interpretation_id: command.interpretation_id,
            source_message_id: proposal.source_message_id,
            source_event: proposal.source_event,
            proposal_event: candidate.proposal.event,
            acceptance_event: candidate.acceptance.event,
            definition: candidate.definition,
            classifier: proposal.classifier,
            scope_provenance: proposal.scope_provenance,
            recorded_at: activated_at
          )
        end

        def activated_event(candidate, command, activated_at)
          Events::DecisionActivatedV1.new(
            decision_id: command.decision_id,
            interpretation_id: command.interpretation_id,
            recorded_event: candidate.recorded_event,
            definition_digest: candidate.definition.digest,
            slot: candidate.slot,
            partitions: candidate.partitions,
            rationale: command.rationale,
            activated_at:
          )
        end

        def slot_writes(slot, decision_head, activated_at)
          return [] unless slot

          stream = @stream_factory.decision_slot(slot.slot_id)
          [
            EventWrite.new(
              stream:,
              event: Events::DecisionSlotOpenedV1.new(
                slot:,
                opened_by: decision_head,
                opened_at: activated_at
              )
            ),
            EventWrite.new(
              stream:,
              event: Events::DecisionSlotHeadChangedV1.new(
                slot_id: slot.slot_id,
                previous_head: nil,
                head: decision_head,
                changed_at: activated_at
              )
            )
          ]
        end

        def partition_writes(states, decision_head, activated_at)
          states.map do |state|
            next_revision = state.latest_revision ? state.latest_revision + 1 : 0
            EventWrite.new(
              stream: @stream_factory.decision_partition(state.partition.partition_id),
              event: Events::DecisionPartitionAdvancedV1.new(
                partition: state.partition,
                partition_revision: next_revision,
                decision: decision_head,
                active_decisions: next_active_decisions(state, decision_head),
                change_kind: "activated",
                advanced_at: activated_at
              )
            )
          end
        end

        def next_active_decisions(state, decision_head)
          (state.active_decisions + [ decision_head ])
            .uniq(&:decision_id)
            .sort_by { _1.decision_id.b }
            .freeze
        end

        def partition_capacity_error(state, command)
          full = state.partition_states.find do |partition_state|
            partition_state.active_decisions.none? { _1.decision_id == command.decision_id } &&
              partition_state.active_decisions.length >= @maximum_active_decisions
          end
          return unless full

          Failure(
            OutcomeError.new(
              code: :decision_partition_capacity_reached,
              message: "DecisionPartition already contains the maximum active Decision heads",
              details: {
                partition_id: full.partition.partition_id,
                active_decision_count: full.active_decisions.length,
                maximum_active_decisions: @maximum_active_decisions
              }
            )
          )
        end

        def decision_exists(event, command)
          Failure(
            OutcomeError.new(
              code: :decision_already_exists,
              message: "Decision ID already has authoritative facts",
              details: {
                decision_id: command.decision_id,
                event_id: event.event_id,
                event_type: event.type
              }
            )
          )
        end

        def interpretation_used(evidence)
          Failure(
            OutcomeError.new(
              code: :interpretation_already_activated,
              message: "Accepted interpretation is already active as another Decision",
              details: {
                interpretation_id: evidence.interpretation_id,
                decision_id: evidence.decision_id,
                event_id: evidence.event.event_id
              }
            )
          )
        end

        def slot_occupied(head, slot)
          Failure(
            OutcomeError.new(
              code: :decision_slot_occupied,
              message: "Exclusive Decision slot already has an active head",
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
