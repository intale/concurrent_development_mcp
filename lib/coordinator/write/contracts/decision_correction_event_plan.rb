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
        write = plan.writes.first
        event = write.event
        unless event.is_a?(Events::DecisionDefinitionCorrectedV1) &&
               write.stream == streams.decision(command.decision_id)
          key.failure("must begin with DecisionDefinitionCorrected on the target Decision")
          return
        end
        unless event.decision_id == command.decision_id &&
               event.interpretation_id == command.interpretation_id &&
               event.previous_head == state.current.head &&
               event.previous_definition_digest == state.current.definition.digest &&
               event.definition == state.candidate.definition &&
               event.previous_slot == state.current.slot &&
               event.slot == state.candidate.slot &&
               event.previous_partitions == state.current.partitions &&
               event.partitions == state.candidate.partitions
          key.failure("correction fact must retain the complete predecessor and candidate")
        end
      end

      def validate_slots(key, plan, state, command, streams)
        expected = expected_slot_events(state)
        writes = plan.writes.drop(1).first(expected.length)
        unless writes.map { _1.event.class } == expected
          key.failure("must contain the exact slot topology transition")
          return expected.length
        end

        correction_head = state.candidate.correction_event
        writes.each do |write|
          event = write.event
          slot = slot_for(state, event)
          unless write.stream == streams.decision_slot(slot.slot_id) && slot_event_valid?(event, slot, command, correction_head)
            key.failure("slot transition does not match its canonical slot and Decision")
          end
        end
        expected.length
      end

      def expected_slot_events(state)
        current = state.current.slot
        corrected = state.candidate.slot
        return [] unless current || corrected
        return [ Events::DecisionSlotHeadChangedV1 ] if current == corrected

        events = []
        events << Events::DecisionSlotHeadChangedV1 if current
        if corrected
          corrected_state = state.slot_states.find { _1.slot.slot_id == corrected.slot_id }
          events << Events::DecisionSlotOpenedV1 unless corrected_state.opened
          events << Events::DecisionSlotHeadChangedV1
        end
        events
      end

      def slot_for(state, event)
        slot_id = event.is_a?(Events::DecisionSlotOpenedV1) ? event.slot.slot_id : event.slot_id
        state.slot_states.find { _1.slot.slot_id == slot_id }.slot
      end

      def slot_event_valid?(event, slot, command, correction_event)
        case event
        when Events::DecisionSlotOpenedV1
          event.slot == slot &&
            event.opened_by.decision_id == command.decision_id &&
            event.opened_by.event == correction_event
        when Events::DecisionSlotHeadChangedV1
          event.slot_id == slot.slot_id &&
            (!event.head || (event.head.decision_id == command.decision_id && event.head.event == correction_event))
        end
      end

      def validate_partitions(key, plan, state, command, streams, slot_count)
        writes = plan.writes.drop(1 + slot_count)
        unless writes.length == state.partition_states.length &&
               writes.all? { _1.event.is_a?(Events::DecisionPartitionAdvancedV1) }
          key.failure("must advance every and only affected DecisionPartition")
          return
        end

        writes.zip(state.partition_states).each do |write, partition_state|
          event = write.event
          expected_revision = partition_state.latest_revision ? partition_state.latest_revision + 1 : 0
          unless write.stream == streams.decision_partition(partition_state.partition.partition_id) &&
                 event.partition == partition_state.partition &&
                 event.partition_revision == expected_revision &&
                 event.decision.decision_id == command.decision_id &&
                 event.decision.event == state.candidate.correction_event &&
                 event.change_kind == "corrected"
            key.failure("DecisionPartition write does not match its authoritative predecessor")
          end
        end
      end
    end
  end
end
