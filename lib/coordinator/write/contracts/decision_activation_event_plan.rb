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
        events = plan.events
        expected_count = 2 + candidate.partitions.length + (candidate.slot ? 2 : 0)

        key(:plan).failure("must contain the complete activation event set") unless events.length == expected_count
        validate_decision_writes(key, plan, candidate, command, streams)
        validate_slot_writes(key, plan, candidate, command, streams)
        validate_partition_writes(key, plan, state, command, streams)
      end

      private

      def validate_decision_writes(key, plan, candidate, command, streams)
        writes = plan.writes.first(2)
        expected_stream = streams.decision(command.decision_id)
        unless writes.map(&:event).map(&:class) == [ Events::DecisionRecordedV1, Events::DecisionActivatedV1 ]
          key.failure("must begin with DecisionRecorded and DecisionActivated")
          return
        end
        key.failure("Decision facts must share the command Decision stream") unless writes.all? { _1.stream == expected_stream }

        recorded, activated = writes.map(&:event)
        unless recorded.decision_id == command.decision_id && activated.decision_id == command.decision_id
          key.failure("Decision fact identities must match the command")
        end
        unless recorded.interpretation_id == command.interpretation_id && activated.interpretation_id == command.interpretation_id
          key.failure("Interpretation identities must match the command")
        end
        key.failure("activation must reference its planned recorded fact") unless activated.recorded_event == candidate.recorded_event
        key.failure("activation must retain the normalized definition digest") unless activated.definition_digest == candidate.definition.digest
        key.failure("activation must retain the derived partitions") unless activated.partitions == candidate.partitions
      end

      def validate_slot_writes(key, plan, candidate, command, streams)
        offset = 2
        slot_writes = plan.writes.slice(offset, candidate.slot ? 2 : 0)
        return key.failure("set-union activation must not write a DecisionSlot") unless candidate.slot || slot_writes.empty?
        return unless candidate.slot

        unless slot_writes.map(&:event).map(&:class) == [ Events::DecisionSlotOpenedV1, Events::DecisionSlotHeadChangedV1 ]
          key.failure("exclusive activation must open and assign exactly one DecisionSlot")
          return
        end
        expected_stream = streams.decision_slot(candidate.slot.slot_id)
        key.failure("DecisionSlot facts must share the canonical slot stream") unless slot_writes.all? { _1.stream == expected_stream }

        opened, changed = slot_writes.map(&:event)
        key.failure("DecisionSlot identity must retain the canonical slot") unless opened.slot == candidate.slot && changed.slot_id == candidate.slot.slot_id
        key.failure("new DecisionSlot must have no previous head") unless changed.previous_head.nil?
        unless opened.opened_by == changed.head && changed.head.decision_id == command.decision_id
          key.failure("DecisionSlot head must reference the activation")
        end
      end

      def validate_partition_writes(key, plan, state, command, streams)
        offset = state.candidate.slot ? 4 : 2
        writes = plan.writes.drop(offset)
        unless writes.length == state.partition_states.length && writes.all? { _1.event.is_a?(Events::DecisionPartitionAdvancedV1) }
          key.failure("must advance every and only derived DecisionPartition")
          return
        end

        writes.zip(state.partition_states).each do |write, partition_state|
          event = write.event
          expected_revision = partition_state.latest_revision ? partition_state.latest_revision + 1 : 0
          unless write.stream == streams.decision_partition(partition_state.partition.partition_id) &&
                 event.partition == partition_state.partition &&
                 event.partition_revision == expected_revision &&
                 event.decision.decision_id == command.decision_id
            key.failure("DecisionPartition write does not match its authoritative predecessor")
          end
        end
      end
    end
  end
end
