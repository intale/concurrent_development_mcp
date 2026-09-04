# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DecisionActivationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::Decisions::ActivationState))
        required(:command).value(Types.Instance(Commands::ActivateDecision))
        required(:stream_factory).value(Types.Instance(StreamFactory))
      end

      rule(:plan, :state, :command, :stream_factory) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        streams = values[:stream_factory]
        candidate = state.candidate
        expected_count = 3 + candidate.partitions.length + (candidate.slot ? 2 : 0)

        key(:plan).failure("must contain the complete activation fact set") unless plan.events.length == expected_count
        validate_decision_facts(key, plan, candidate, command, streams)
        validate_slot_facts(key, plan, candidate, command, streams)
        validate_partition_facts(key, plan, state, command, streams)
      end

      private

      def validate_decision_facts(key, plan, candidate, command, streams)
        writes = plan.writes.first(3)
        expected_types = [
          Events::DecisionRecordedV2,
          Events::DecisionDerivedFromInterpretationV1,
          Events::DecisionActivatedV2
        ]
        unless writes.map { _1.event.class } == expected_types
          key.failure("must begin with recorded, derivation, and activation facts")
          return
        end
        expected_stream = streams.decision(command.decision_id)
        key.failure("Decision facts must share the command Decision stream") unless writes.all? { _1.stream == expected_stream }

        recorded, derived, activated = writes.map(&:event)
        unless [ recorded, derived, activated ].all? { _1.decision_id == command.decision_id } &&
               [ recorded, derived, activated ].all? { _1.interpretation_id == command.interpretation_id } &&
               recorded.definition == candidate.definition.document
          key.failure("Decision facts must retain the decided identities and definition")
        end
      end

      def validate_slot_facts(key, plan, candidate, command, streams)
        writes = plan.writes.drop(3).first(candidate.slot ? 2 : 0)
        return key.failure("set-union activation must not write a DecisionSlot") unless candidate.slot || writes.empty?
        return unless candidate.slot

        unless writes.map { _1.event.class } == [ Events::DecisionSlotOpenedV2, Events::DecisionSlotHeadChangedV2 ]
          key.failure("exclusive activation must open and assign exactly one DecisionSlot")
          return
        end
        expected_stream = streams.decision_slot(candidate.slot.slot_id)
        key.failure("DecisionSlot facts must share the canonical slot stream") unless writes.all? { _1.stream == expected_stream }

        opened, changed = writes.map(&:event)
        unless opened.slot_id == candidate.slot.slot_id &&
               opened.slot == candidate.slot.document &&
               opened.opened_by == command.decision_id &&
               changed.slot_id == candidate.slot.slot_id &&
               changed.head.decision_id == command.decision_id &&
               changed.head.event == candidate.activated_event
          key.failure("DecisionSlot facts must retain the canonical slot and activation head")
        end
      end

      def validate_partition_facts(key, plan, state, command, streams)
        writes = plan.writes.drop(state.candidate.slot ? 5 : 3)
        unless writes.length == state.partition_states.length &&
               writes.all? { _1.event.is_a?(Events::DecisionAddedToPartitionV1) }
          key.failure("must add the Decision to every and only derived partition")
          return
        end

        writes.zip(state.partition_states).each do |write, partition_state|
          event = write.event
          expected_revision = partition_state.latest_revision ? partition_state.latest_revision + 1 : 0
          unless write.stream == streams.decision_partition(partition_state.partition.partition_id) &&
                 event.partition_id == partition_state.partition.partition_id &&
                 event.partition_revision == expected_revision &&
                 event.decision_id == command.decision_id
            key.failure("Decision partition fact does not match its authoritative predecessor")
          end
        end
      end
    end
  end
end
