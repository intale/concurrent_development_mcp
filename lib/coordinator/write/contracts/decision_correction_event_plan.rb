# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DecisionCorrectionEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::Decisions::CorrectionState))
        required(:command).value(Types.Instance(Commands::CorrectDecision))
        required(:stream_factory).value(Types.Instance(StreamFactory))
      end

      rule(:plan, :state, :command, :stream_factory) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        streams = values[:stream_factory]
        validate_correction(key, plan, state, command, streams)
        slot_count = validate_slots(key, plan, state, command, streams)
        validate_partitions(key, plan, state, command, streams, slot_count)
      end

      private

      def validate_correction(key, plan, state, command, streams)
        writes = plan.writes.first(2)
        unless writes.map { _1.event.class } == [
          Events::DecisionDerivedFromInterpretationV1,
          Events::DecisionDefinitionCorrectedV2
        ] && writes.all? { _1.stream == streams.decision(command.decision_id) }
          key.failure("must begin with correction and interpretation-derivation facts")
          return
        end

        derived, correction = writes.map(&:event)
        unless correction.decision_id == command.decision_id &&
               correction.interpretation_id == command.interpretation_id &&
               correction.definition == state.candidate.definition.document &&
               derived.decision_id == command.decision_id &&
               derived.interpretation_id == command.interpretation_id
          key.failure("correction facts must retain only the decided definition and identities")
        end
      end

      def validate_slots(key, plan, state, command, streams)
        expected = expected_slot_events(state)
        writes = plan.writes.drop(2).first(expected.length)
        unless writes.map { _1.event.class } == expected
          key.failure("must contain the exact slot topology transition")
          return expected.length
        end

        writes.each do |write|
          event = write.event
          slot = slot_for(state, event)
          unless write.stream == streams.decision_slot(slot.slot_id) &&
                 slot_event_valid?(event, slot, command, state.candidate.correction_event)
            key.failure("slot transition does not match its canonical slot and Decision")
          end
        end
        expected.length
      end

      def expected_slot_events(state)
        current = state.current.slot
        corrected = state.candidate.slot
        return [] unless current || corrected
        return [ Events::DecisionSlotHeadChangedV2 ] if current == corrected

        events = []
        events << Events::DecisionSlotHeadChangedV2 if current
        if corrected
          corrected_state = state.slot_states.find { _1.slot.slot_id == corrected.slot_id }
          events << Events::DecisionSlotOpenedV2 unless corrected_state.opened
          events << Events::DecisionSlotHeadChangedV2
        end
        events
      end

      def slot_for(state, event)
        slot_id = event.slot_id
        state.slot_states.find { _1.slot.slot_id == slot_id }.slot
      end

      def slot_event_valid?(event, slot, command, correction_event)
        case event
        when Events::DecisionSlotOpenedV2
          event.slot_id == slot.slot_id &&
            event.slot == slot.document &&
            event.opened_by == command.decision_id
        when Events::DecisionSlotHeadChangedV2
          event.slot_id == slot.slot_id &&
            (!event.head || (
              event.head.decision_id == command.decision_id &&
              event.head.event == correction_event
            ))
        end
      end

      def validate_partitions(key, plan, state, command, streams, slot_count)
        writes = plan.writes.drop(2 + slot_count)
        expected = partition_changes(state, command.decision_id)
        unless writes.length == expected.length &&
               writes.all? do |write|
                 write.event.is_a?(Events::DecisionAddedToPartitionV1) ||
                   write.event.is_a?(Events::DecisionRemovedFromPartitionV1)
               end
          key.failure("must contain exactly the changed partition memberships")
          return
        end

        writes.zip(expected).each do |write, expectation|
          partition_state, event_class = expectation
          event = write.event
          expected_revision = partition_state.latest_revision ? partition_state.latest_revision + 1 : 0
          unless event.is_a?(event_class) &&
                 write.stream == streams.decision_partition(partition_state.partition.partition_id) &&
                 event.partition_id == partition_state.partition.partition_id &&
                 event.partition_revision == expected_revision &&
                 event.decision_id == command.decision_id
            key.failure("partition membership fact does not match its authoritative predecessor")
          end
        end
      end

      def partition_changes(state, decision_id)
        corrected_ids = state.candidate.partitions.map(&:partition_id)
        state.partition_states.filter_map do |partition_state|
          current = partition_state.active_decisions.any? { _1.decision_id == decision_id }
          corrected = corrected_ids.include?(partition_state.partition.partition_id)
          next if current == corrected

          [ partition_state, corrected ? Events::DecisionAddedToPartitionV1 : Events::DecisionRemovedFromPartitionV1 ]
        end
      end
    end
  end
end
