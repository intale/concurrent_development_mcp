# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteActivateDecision < Dry::Operation
      TOOL_NAME = "decision_activate"

      def initialize(
        event_store:,
        preparer: PrepareActivateDecision.new,
        candidate_preparer: Domain::Decisions::PrepareActivation.new,
        decider: Domain::Decisions::Activate.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandCompletionBuilder.new,
        event_plan_contract: Contracts::DecisionActivationEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @candidate_preparer = candidate_preparer
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @event_plan_contract = event_plan_contract
      end

      def call(input)
        command = step @preparer.call(input)
        step call_command(command)
      end

      def call_command(command, caused_by: nil)
        steps do
          preparation = prepare_logical_values(command)
          step @event_store.multiple { execute_attempt(command:, preparation:, caused_by:) }
        end
      end

      private

      def prepare_logical_values(command)
        DecisionActivationPreparationV1.new(
          activated_at: @clock.now,
          input_digest: @input_digest.decision_activate(command),
          recorded_event_id: @id_generator.uuid_v7,
          activated_event_id: @id_generator.uuid_v7,
          slot_opened_event_id: @id_generator.uuid_v7,
          slot_head_event_id: @id_generator.uuid_v7,
          partition_event_ids: Array.new(32) { @id_generator.uuid_v7 },
          completion_event_id: @id_generator.uuid_v7
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        replay = replay_result(command:, input_digest: preparation.input_digest)
        return replay if replay

        existing_decision = load_existing_decision(command.decision_id)
        proposal = load_proposal(command.interpretation_id)
        acceptance = load_acceptance(command.interpretation_id)
        existing_activation = load_existing_activation(command.interpretation_id)
        candidate = @candidate_preparer.call(
          command:,
          proposal:,
          acceptance:,
          activated_at: preparation.activated_at,
          recorded_event: future_event_reference(
            event_id: preparation.recorded_event_id,
            type: "DecisionRecorded",
            decision_id: command.decision_id,
            stream_revision: 0
          ),
          activated_event: future_event_reference(
            event_id: preparation.activated_event_id,
            type: "DecisionActivated",
            decision_id: command.decision_id,
            stream_revision: 1
          )
        )
        return candidate if candidate.failure?

        state = load_activation_state(
          candidate: candidate.value!,
          existing_decision:,
          existing_activation:
        )
        decision = @decider.call(state:, command:, activated_at: preparation.activated_at)
        return decision if decision.failure?

        plan = apply_event_plan_contract(decision.value!, state, command)
        persisted_events = persist_domain_plan(
          plan,
          command:,
          preparation:,
          caused_by:
        )
        activation = plan.events.find { _1.is_a?(Events::DecisionActivatedV1) }
        partitions = partition_receipts(plan, persisted_events)
        completion = @completion_builder.decision_activate(
          command:,
          activation:,
          partitions:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.activated_at
        )
        persist_completion(
          completion,
          command:,
          event_id: preparation.completion_event_id,
          caused_by:
        )

        Success(completion)
      end

      def replay_result(command:, input_digest:)
        completion = load_completion(command.command_id)
        return unless completion

        if completion.tool_name == TOOL_NAME && completion.canonical_input_digest == input_digest
          Success(completion)
        else
          Failure(
            OutcomeError.new(
              code: :command_id_reused,
              message: "Command ID is already bound to another tool or input",
              details: {
                command_id: command.command_id,
                existing_tool_name: completion.tool_name,
                existing_input_digest: completion.canonical_input_digest,
                requested_tool_name: TOOL_NAME,
                requested_input_digest: input_digest
              }
            )
          )
        end
      end

      def load_completion(command_id)
        event = @event_store.read(
          @stream_factory.command(command_id),
          EventQueries::COMMAND_COMPLETION
        ).first
        event && load_event(event)
      end

      def load_existing_decision(decision_id)
        event = @event_store.read(
          @stream_factory.decision(decision_id),
          EventQueries::DECISION_EXISTENCE
        ).first
        event && event_reference(event)
      end

      def load_proposal(interpretation_id)
        event = @event_store.read_global_marked(
          EventQueries.interpretation_proposal(interpretation_marker(interpretation_id))
        ).first
        return unless event

        Interpretations::InterpretationProposalEvidenceV1.new(
          proposal: load_event(event),
          event: event_reference(event)
        )
      end

      def load_acceptance(interpretation_id)
        event = @event_store.read_global_marked(
          EventQueries.interpretation_acceptance(lifecycle_marker(interpretation_id))
        ).first
        return unless event

        Decisions::InterpretationAcceptanceEvidenceV1.new(
          acceptance: load_event(event),
          event: event_reference(event)
        )
      end

      def load_existing_activation(interpretation_id)
        event = @event_store.read_global_marked(
          EventQueries.decision_activation(activation_marker(interpretation_id))
        ).first
        return unless event

        payload = load_event(event)
        Decisions::DecisionActivationEvidenceV1.new(
          decision_id: payload.decision_id,
          interpretation_id: payload.interpretation_id,
          event: event_reference(event)
        )
      end

      def load_activation_state(candidate:, existing_decision:, existing_activation:)
        Domain::Decisions::ActivationState.new(
          candidate:,
          existing_decision:,
          existing_activation:,
          slot_head: load_slot_head(candidate.slot),
          partition_states: candidate.partitions.map { load_partition_state(_1) }
        )
      end

      def load_slot_head(slot)
        return unless slot

        event = @event_store.read_grouped(
          @stream_factory.decision_slot(slot.slot_id),
          EventQueries::DECISION_SLOT_LATEST
        ).find { _1.type == "DecisionSlotHeadChanged" }
        event && load_event(event).head
      end

      def load_partition_state(partition)
        event = @event_store.read_grouped(
          @stream_factory.decision_partition(partition.partition_id),
          EventQueries::DECISION_PARTITION_LATEST
        ).first
        Decisions::DecisionPartitionStateV1.new(
          partition:,
          latest_revision: event&.stream_revision
        )
      end

      def apply_event_plan_contract(plan, state, command)
        result = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          stream_factory: @stream_factory
        )
        return plan if result.success?

        raise ArgumentError, "decision activation plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        partition_index = 0
        definition = plan.events.first.definition
        slot = plan.events.fetch(1).slot
        physical_writes = plan.writes.map do |write|
          event_id, partition_index = event_identity(
            write.event,
            preparation,
            partition_index
          )
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command),
            markers: markers_for(write.event, command, definition:, slot:),
            caused_by:
          )
          [ write.stream, event ]
        end

        physical_writes.chunk_while { |left, right| left.first == right.first }.flat_map do |chunk|
          @event_store.append(chunk.first.first, chunk.map(&:last))
        end
      end

      def event_identity(event, preparation, partition_index)
        case event
        when Events::DecisionRecordedV1
          [ preparation.recorded_event_id, partition_index ]
        when Events::DecisionActivatedV1
          [ preparation.activated_event_id, partition_index ]
        when Events::DecisionSlotOpenedV1
          [ preparation.slot_opened_event_id, partition_index ]
        when Events::DecisionSlotHeadChangedV1
          [ preparation.slot_head_event_id, partition_index ]
        when Events::DecisionPartitionAdvancedV1
          [ preparation.partition_event_ids.fetch(partition_index), partition_index + 1 ]
        end
      end

      def markers_for(event, command, definition:, slot:)
        case event
        when Events::DecisionRecordedV1, Events::DecisionActivatedV1
          decision_markers(command, definition, slot)
        when Events::DecisionSlotOpenedV1, Events::DecisionSlotHeadChangedV1
          slot_markers(slot, command)
        when Events::DecisionPartitionAdvancedV1
          [
            "decision-partition:#{event.partition.partition_id}",
            "topic-root:#{event.partition.topic_root}",
            "decision:#{command.decision_id}",
            "command:#{command.command_id}"
          ]
        end
      end

      def decision_markers(command, definition, slot)
        markers = [
          "decision:#{command.decision_id}",
          activation_marker(command.interpretation_id),
          "topic:#{definition.document.topic.topic_id}",
          "topic-root:#{definition.document.topic_root}",
          "command:#{command.command_id}"
        ]
        markers << slot.compound_marker.marker if slot
        markers
      end

      def slot_markers(slot, command)
        slot.compound_marker.components + [
          slot.compound_marker.marker,
          "decision:#{command.decision_id}",
          "topic-root:#{slot.document.topic_id.split('.', 2).first}",
          "command:#{command.command_id}"
        ]
      end

      def partition_receipts(plan, persisted_events)
        payloads = plan.events.select { _1.is_a?(Events::DecisionPartitionAdvancedV1) }
        events = persisted_events.select { _1.type == "DecisionPartitionAdvanced" }
        payloads.zip(events).map do |payload, event|
          Decisions::DecisionPartitionReceiptV1.new(
            partition: payload.partition,
            partition_revision: event.stream_revision
          )
        end
      end

      def persist_completion(completion, command:, event_id:, caused_by:)
        event = @event_factory.build!(
          event: completion,
          event_id:,
          metadata: command_metadata(command),
          markers: [ "command:#{command.command_id}" ],
          caused_by:
        )
        @event_store.append(@stream_factory.command(command.command_id), [ event ])
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def future_event_reference(event_id:, type:, decision_id:, stream_revision:)
        stream = @stream_factory.decision(decision_id)
        EventReference.new(
          event_id:,
          type:,
          stream_context: stream.context,
          stream_name: stream.stream_name,
          stream_id: stream.stream_id,
          stream_revision:
        )
      end

      def interpretation_marker(interpretation_id)
        "interpretation:#{interpretation_id}"
      end

      def lifecycle_marker(interpretation_id)
        "interpretation-lifecycle:#{interpretation_id}"
      end

      def activation_marker(interpretation_id)
        "interpretation-activation:#{interpretation_id}"
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "decision-activation/v1"
        )
      end
    end
  end
end
