# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteCorrectDecision < Dry::Operation
      TOOL_NAME = "decision_correct"

      def initialize(
        event_store:,
        preparer: PrepareCorrectDecision.new,
        candidate_preparer: Domain::Decisions::PrepareCorrection.new,
        decider: Domain::Decisions::Correct.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        event_plan_contract: Contracts::DecisionCorrectionEventPlan.new
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
        @natural_key_registry = natural_key_registry
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
        DecisionCorrectionPreparationV1.new(
          corrected_at: @clock.now,
          input_digest: @input_digest.decision_correct(command),
          correction_event_id: @id_generator.uuid_v7,
          slot_event_ids: Array.new(3) { @id_generator.uuid_v7 },
          partition_event_ids: Array.new(32) { @id_generator.uuid_v7 },
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        current = load_current_decision(command.decision_id)
        return current if current.failure?

        current = current.value!
        proposal = load_proposal(command.interpretation_id)
        acceptance = load_acceptance(command.interpretation_id)
        candidate = @candidate_preparer.call(
          command:,
          current:,
          proposal:,
          acceptance:,
          corrected_at: preparation.corrected_at,
          correction_event: future_correction_reference(
            event_id: preparation.correction_event_id,
            decision_id: command.decision_id,
            stream_revision: current.head.decision_revision + 1
          )
        )
        return candidate if candidate.failure?

        candidate = resolve_candidate_slot(candidate.value!)
        return candidate if candidate.failure?

        state = load_correction_state(current:, candidate: candidate.value!, command:)
        return state if state.failure?

        state = state.value!
        decision = @decider.call(state:, command:, corrected_at: preparation.corrected_at)
        return decision if decision.failure?

        plan = apply_event_plan_contract(decision.value!, state, command)
        persisted_events = persist_domain_plan(plan, state:, command:, preparation:, caused_by:)
        correction = plan.events.first
        partitions = partition_receipts(plan, persisted_events)
        completion = @completion_builder.decision_correct(
          command:,
          correction:,
          correction_event: event_reference(persisted_events.first),
          partitions:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.corrected_at
        )

        Success(completion)
      end

      def resolve_candidate_slot(candidate)
        proposed = candidate.slot
        return Success(candidate) unless proposed

        result = @natural_key_registry.find(
          selector: NaturalKeys::Registry::SelectorV1.new(
            stream_context: "HumanGuidance",
            stream_name: "DecisionSlot",
            event_type: "DecisionSlotOpened",
            marker: proposed.compound_marker.marker
          ),
          identity_from: ->(event) { decision_slot_identity_from(event, proposed) }
        )
        return slot_registry_failure(result.failure) if result.failure?
        return Success(candidate) unless result.value!

        slot = Decisions::DecisionSlotV1.new(
          slot_id: result.value!.identity,
          document: proposed.document,
          compound_marker: proposed.compound_marker
        )
        Success(
          Decisions::DecisionCorrectionCandidateV1.new(
            proposal: candidate.proposal,
            acceptance: candidate.acceptance,
            definition: candidate.definition,
            slot:,
            partitions: candidate.partitions,
            correction_event: candidate.correction_event
          )
        )
      end

      def decision_slot_identity_from(event, proposed)
        opening = load_event(event)
        return unless opening.is_a?(Events::DecisionSlotOpenedV1)
        return unless opening.slot.document == proposed.document

        opening.slot.slot_id
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError
        nil
      end

      def slot_registry_failure(error)
        Failure(
          OutcomeError.new(
            code: :decision_slot_registry_invalid,
            message: error.message,
            details: error.to_h
          )
        )
      end

      def load_current_decision(decision_id)
        events = @event_store.read_grouped(
          @stream_factory.decision(decision_id),
          EventQueries::DECISION_CORRECTION_STATE
        )
        recorded_event = events.find { _1.type == "DecisionRecorded" }
        return decision_not_found(decision_id) unless recorded_event

        activated_event = events.find { _1.type == "DecisionActivated" }
        return decision_not_active(decision_id, recorded_event) unless activated_event

        correction_event = events.find { _1.type == "DecisionDefinitionCorrected" }
        recorded = load_event(recorded_event)
        activation = load_event(activated_event)
        correction = correction_event && load_event(correction_event)
        head_event = correction_event || activated_event
        definition = correction ? correction.definition : recorded.definition
        slot = correction ? correction.slot : activation.slot
        partitions = correction ? correction.partitions : activation.partitions

        Success(
          Decisions::DecisionCurrentStateV1.new(
            decision_id:,
            definition:,
            head: Decisions::DecisionHeadV1.new(
              decision_id:,
              decision_revision: head_event.stream_revision,
              event: event_reference(head_event)
            ),
            slot:,
            partitions:
          )
        )
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

      def load_correction_state(current:, candidate:, command:)
        slots = [ current.slot, candidate.slot ].compact.uniq { _1.slot_id }.sort_by { _1.slot_id.b }
        partitions = merge_partitions(current.partitions, candidate.partitions)
        return partition_limit(command, partitions.length) if partitions.length > 32

        Success(
          Domain::Decisions::CorrectionState.new(
            current:,
            candidate:,
            slot_states: slots.map { load_slot_state(_1) },
            partition_states: partitions.map { load_partition_state(_1) }
          )
        )
      end

      def load_slot_state(slot)
        events = @event_store.read_grouped(
          @stream_factory.decision_slot(slot.slot_id),
          EventQueries::DECISION_SLOT_LATEST
        )
        opening_event = events.find { _1.type == "DecisionSlotOpened" }
        change_event = events.find { _1.type == "DecisionSlotHeadChanged" }
        opening = opening_event && load_event(opening_event)
        change = change_event && load_event(change_event)
        Decisions::DecisionSlotStateV1.new(
          slot:,
          opened: !opening.nil?,
          head: change ? change.head : opening&.opened_by
        )
      end

      def load_partition_state(partition)
        event = @event_store.read_grouped(
          @stream_factory.decision_partition(partition.partition_id),
          EventQueries::DECISION_PARTITION_LATEST
        ).first
        payload = event && load_event(event)
        Decisions::DecisionPartitionStateV1.new(
          partition:,
          latest_revision: event&.stream_revision,
          active_decisions: payload ? payload.active_decisions : []
        )
      end

      def merge_partitions(current, candidate)
        (current + candidate)
          .uniq { _1.partition_id }
          .sort_by { _1.partition_id.b }
          .freeze
      end

      def apply_event_plan_contract(plan, state, command)
        result = @event_plan_contract.call(
          plan:,
          state:,
          command:,
          stream_factory: @stream_factory
        )
        return plan if result.success?

        raise ArgumentError, "decision correction plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, state:, command:, preparation:, caused_by:)
        slot_index = 0
        partition_index = 0
        slots = [ state.current.slot, state.candidate.slot ].compact.to_h { [ _1.slot_id, _1 ] }
        physical_writes = plan.writes.map do |write|
          event_id, slot_index, partition_index = event_identity(
            write.event,
            preparation,
            slot_index,
            partition_index
          )
          event = @event_factory.build!(
            event: write.event,
            event_id:,
            metadata: command_metadata(command),
            markers: markers_for(
              write.event,
              command,
              slots:,
              current_definition: state.current.definition
            ),
            caused_by:
          )
          [ write.stream, event ]
        end

        physical_writes.chunk_while { |left, right| left.first == right.first }.flat_map do |chunk|
          @event_store.append(chunk.first.first, chunk.map(&:last))
        end
      end

      def event_identity(event, preparation, slot_index, partition_index)
        case event
        when Events::DecisionDefinitionCorrectedV1
          [ preparation.correction_event_id, slot_index, partition_index ]
        when Events::DecisionSlotOpenedV1, Events::DecisionSlotHeadChangedV1
          [ preparation.slot_event_ids.fetch(slot_index), slot_index + 1, partition_index ]
        when Events::DecisionPartitionAdvancedV1
          [ preparation.partition_event_ids.fetch(partition_index), slot_index, partition_index + 1 ]
        end
      end

      def markers_for(event, command, slots:, current_definition:)
        case event
        when Events::DecisionDefinitionCorrectedV1
          correction_markers(event, command, current_definition)
        when Events::DecisionSlotOpenedV1
          slot_markers(event.slot, command)
        when Events::DecisionSlotHeadChangedV1
          slot_markers(slots.fetch(event.slot_id), command)
        when Events::DecisionPartitionAdvancedV1
          [
            "decision-partition:#{event.partition.partition_id}",
            "topic-root:#{event.partition.topic_root}",
            "decision:#{command.decision_id}",
            "command:#{command.command_id}"
          ]
        end
      end

      def correction_markers(event, command, current_definition)
        slots = [ event.previous_slot, event.slot ].compact
        topic_ids = [
          current_definition.document.topic.topic_id,
          event.definition.document.topic.topic_id
        ].uniq
        topic_roots = (event.previous_partitions + event.partitions).map(&:topic_root).uniq
        [
          "decision:#{command.decision_id}",
          "interpretation-correction:#{command.interpretation_id}",
          *topic_ids.map { "topic:#{_1}" },
          *topic_roots.map { "topic-root:#{_1}" },
          *slots.map { _1.compound_marker.marker },
          "command:#{command.command_id}"
        ].uniq
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

      def future_correction_reference(event_id:, decision_id:, stream_revision:)
        stream = @stream_factory.decision(decision_id)
        EventReference.new(
          event_id:,
          type: "DecisionDefinitionCorrected",
          stream_context: stream.context,
          stream_name: stream.stream_name,
          stream_id: stream.stream_id,
          stream_revision:
        )
      end

      def decision_not_found(decision_id)
        Failure(
          OutcomeError.new(
            code: :decision_not_found,
            message: "Decision does not exist",
            details: { decision_id: }
          )
        )
      end

      def decision_not_active(decision_id, event)
        Failure(
          OutcomeError.new(
            code: :decision_not_active,
            message: "Decision has not been activated",
            details: { decision_id:, event: event_reference(event).to_h }
          )
        )
      end

      def partition_limit(command, count)
        Failure(
          OutcomeError.new(
            code: :decision_partition_limit_reached,
            message: "Decision correction affects more than 32 unique partitions",
            details: {
              decision_id: command.decision_id,
              partition_count: count,
              maximum_partition_count: 32
            }
          )
        )
      end

      def interpretation_marker(interpretation_id)
        "interpretation:#{interpretation_id}"
      end

      def lifecycle_marker(interpretation_id)
        "interpretation-lifecycle:#{interpretation_id}"
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "decision-correction/v1"
        )
      end
    end
  end
end
