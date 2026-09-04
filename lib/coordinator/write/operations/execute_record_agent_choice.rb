# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class ExecuteRecordAgentChoice < Dry::Operation
      TOOL_NAME = "agent_choice_record"
      MAXIMUM_PARTITIONS = 8
      MAXIMUM_ACTIVE_DECISIONS = 32

      def initialize(
        event_store:,
        preparer: PrepareRecordAgentChoice.new,
        partition_selector: DecisionContexts::PartitionSelector.new,
        resolver: DecisionContexts::Resolver.new,
        context_builder: DecisionContexts::Builder.new,
        decider: Domain::AgentChoices::Record.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        completion_builder: CommandResultBuilder.new,
        natural_key_registry: NaturalKeys::Registry.new(event_store:),
        canonical_json: CanonicalJson.new,
        decision_slot_builder: Decisions::DecisionSlotBuilder.new,
        decision_partition_builder: Decisions::DecisionPartitionBuilder.new,
        event_plan_contract: Contracts::AgentChoiceEventPlan.new
      )
        @event_store = event_store
        @preparer = preparer
        @partition_selector = partition_selector
        @resolver = resolver
        @context_builder = context_builder
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @completion_builder = completion_builder
        @natural_key_registry = natural_key_registry
        @canonical_json = canonical_json
        @decision_slot_builder = decision_slot_builder
        @decision_partition_builder = decision_partition_builder
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
        AgentChoicePreparationV1.new(
          recorded_at: @clock.now,
          input_digest: @input_digest.agent_choice_record(command),
          recorded_event_id: @id_generator.uuid_v7,
          accepted_event_id: @id_generator.uuid_v7,
        )
      end

      def execute_attempt(command:, preparation:, caused_by:)
        state = load_state(command, preparation)
        return state if state.failure?

        decision = @decider.call(
          state: state.value!,
          command:
        )
        return decision if decision.failure?

        plan = apply_event_plan_contract(
          decision.value!,
          command:,
          context: state.value!.current_context
        )
        persisted_events = persist_domain_plan(plan, command:, preparation:, caused_by:)
        acceptance = plan.events.fetch(1)
        completion = @completion_builder.agent_choice_record(
          command:,
          recorded: plan.events.fetch(0),
          acceptance:,
          input_digest: preparation.input_digest,
          persisted_events:,
          completed_at: preparation.recorded_at
        )

        Success(completion)
      end

      def load_state(command, preparation)
        partitions = @partition_selector.call(command.context)
        return context_limit(partition_count: partitions.length, active_decision_count: 0) if partitions.length > MAXIMUM_PARTITIONS

        observations = load_observations(partitions)
        return observations if observations.failure?

        heads = exact_heads(observations.value!)
        if heads.length > MAXIMUM_ACTIVE_DECISIONS
          return context_limit(
            partition_count: partitions.length,
            active_decision_count: heads.length
          )
        end

        decisions = load_decisions(heads)
        return decisions if decisions.failure?

        resolution = @resolver.call(
          context: command.context,
          observations: observations.value!,
          decisions: decisions.value!,
          resolved_at: preparation.recorded_at
        )
        current_context = @context_builder.call(
          context: command.context,
          observations: observations.value!,
          resolution:,
          resolved_at: preparation.recorded_at
        )
        Success(
          Domain::AgentChoices::State.new(
            attempt: load_attempt_state(command.context.attempt_id),
            existing_choice: load_existing_choice(command.choice_id),
            current_context:,
            resolution:
          )
        )
      end

      def load_observations(partitions)
        observations = []
        partitions.each do |partition|
          events = @event_store.read(
            @stream_factory.decision_partition(partition.partition_id),
            EventQueries::DECISION_PARTITION_STATE
          )
          if events.empty?
            observations << DecisionContexts::PartitionObservationV1.new(
              partition:,
              partition_revision: nil,
              event: nil,
              active_decisions: []
            )
            next
          end

          active = {}
          events.each do |event|
            payload = load_event(event)
            case payload
            when Events::DecisionPartitionAdvancedV1
              invalid = invalid_partition_snapshot(partition, event, payload)
              return invalid if invalid

              active = payload.active_decisions.to_h { [ _1.decision_id, _1 ] }
            when Events::DecisionAddedToPartitionV1
              unless payload.partition_id == partition.partition_id &&
                     payload.partition_revision == event.stream_revision
                return invalid_partition_fact(partition, event)
              end
              head = load_decision_head(payload.decision_id)
              active[payload.decision_id] = head if head
            when Events::DecisionRemovedFromPartitionV1
              unless payload.partition_id == partition.partition_id &&
                     payload.partition_revision == event.stream_revision
                return invalid_partition_fact(partition, event)
              end
              active.delete(payload.decision_id)
            end
          end

          observations << DecisionContexts::PartitionObservationV1.new(
            partition:,
            partition_revision: events.last.stream_revision,
            event: event_reference(events.last),
            active_decisions: active.values.sort_by { _1.decision_id.b }
          )
        end
        Success(observations.freeze)
      end

      def invalid_partition_fact(partition, event)
        Failure(
          OutcomeError.new(
            code: :decision_partition_state_invalid,
            message: "DecisionPartition membership fact violates its authoritative invariant",
            details: {
              partition_id: partition.partition_id,
              stream_revision: event.stream_revision,
              reason: "membership_fact_invalid"
            }
          )
        )
      end

      def invalid_partition_snapshot(partition, event, payload)
        heads = payload.active_decisions
        unique_and_ordered = heads.map(&:decision_id).uniq.length == heads.length &&
                             heads == heads.sort_by { _1.decision_id.b }
        exact_heads = heads.all? do |head|
          head.decision_revision == head.event.stream_revision &&
            head.event.stream_context == "HumanGuidance" &&
            head.event.stream_name == "Decision" &&
            head.event.stream_id == head.decision_id
        end
        return if payload.partition == partition &&
                  payload.partition_revision == event.stream_revision &&
                  unique_and_ordered && exact_heads

        Failure(
          OutcomeError.new(
            code: :decision_partition_state_invalid,
            message: "DecisionPartition snapshot violates its authoritative invariant",
            details: {
              partition_id: partition.partition_id,
              stream_revision: event.stream_revision,
              reason: "snapshot_invariant_violated"
            }
          )
        )
      end

      def exact_heads(observations)
        observations.flat_map(&:active_decisions)
          .uniq { [ _1.decision_id, _1.event.event_id ] }
          .sort_by { [ _1.decision_id.b, _1.event.event_id.b ] }
      end

      def load_decisions(heads)
        decisions = []
        heads.each do |head|
          decision = load_current_decision(head)
          return decision if decision.failure?

          decisions << decision.value!
        end
        Success(decisions.freeze)
      end

      def load_current_decision(expected_head)
        events = @event_store.read_grouped(
          @stream_factory.decision(expected_head.decision_id),
          EventQueries::DECISION_CORRECTION_STATE
        )
        recorded_event = events.find { _1.type == "DecisionRecorded" }
        activated_event = events.find { _1.type == "DecisionActivated" }
        correction_event = events.find { _1.type == "DecisionDefinitionCorrected" }
        return invalid_decision_head(expected_head, nil) unless recorded_event && activated_event

        recorded = load_event(recorded_event)
        activation = load_event(activated_event)
        correction = correction_event && load_event(correction_event)
        head_event = correction_event || activated_event
        current = Decisions::DecisionCurrentStateV1.new(
          decision_id: expected_head.decision_id,
          definition: normalize_definition(correction ? correction.definition : recorded.definition),
          head: Decisions::DecisionHeadV1.new(
            decision_id: expected_head.decision_id,
            decision_revision: head_event.stream_revision,
            event: event_reference(head_event)
          ),
          slot: current_slot(correction:, activation:, definition_payload: correction ? correction.definition : recorded.definition),
          partitions: current_partitions(
            correction:,
            activation:,
            definition_payload: correction ? correction.definition : recorded.definition
          )
        )
        return Success(current) if current.head == expected_head

        invalid_decision_head(expected_head, current.head)
      end

      def normalize_definition(value)
        return value if value.is_a?(Decisions::DecisionDefinitionV1)

        Decisions::DecisionDefinitionV1.new(
          document: value,
          digest: @canonical_json.sha256(value.to_h)
        )
      end

      def current_slot(correction:, activation:, definition_payload:)
        return correction.slot if correction.is_a?(Events::DecisionDefinitionCorrectedV1)
        return activation.slot if !correction && activation.is_a?(Events::DecisionActivatedV1)

        proposed = @decision_slot_builder.call(normalize_definition(definition_payload))
        return unless proposed

        result = @natural_key_registry.find(
          selector: NaturalKeys::Registry::SelectorV1.new(
            stream_context: "HumanGuidance",
            stream_name: "DecisionSlot",
            event_type: "DecisionSlotOpened",
            marker: proposed.compound_marker.marker
          ),
          identity_from: ->(event) { decision_slot_identity_from(event, proposed) }
        )
        raise KeyError, result.failure.message if result.failure?
        raise KeyError, "active Decision slot is not registered" unless result.value!

        Decisions::DecisionSlotV1.new(
          slot_id: result.value!.identity,
          document: proposed.document,
          compound_marker: proposed.compound_marker
        )
      end

      def current_partitions(correction:, activation:, definition_payload:)
        return correction.partitions if correction.is_a?(Events::DecisionDefinitionCorrectedV1)
        return activation.partitions if !correction && activation.is_a?(Events::DecisionActivatedV1)

        @decision_partition_builder.call(normalize_definition(definition_payload))
      end

      def decision_slot_identity_from(event, proposed)
        opening = load_event(event)
        case opening
        when Events::DecisionSlotOpenedV1
          opening.slot.slot_id if opening.slot.document == proposed.document
        when Events::DecisionSlotOpenedV2
          opening.slot_id if opening.slot == proposed.document
        end
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch,
             Dry::Struct::Error, KeyError, ArgumentError
        nil
      end

      def load_decision_head(decision_id)
        event = @event_store.read_grouped(
          @stream_factory.decision(decision_id),
          EventQueries::DECISION_CORRECTION_STATE
        ).select { %w[DecisionDefinitionCorrected DecisionActivated].include?(_1.type) }
          .max_by(&:stream_revision)
        return unless event

        Decisions::DecisionHeadV1.new(
          decision_id:,
          decision_revision: event.stream_revision,
          event: event_reference(event)
        )
      end

      def invalid_decision_head(expected, current)
        Failure(
          OutcomeError.new(
            code: :decision_partition_state_invalid,
            message: "DecisionPartition does not reference the exact current Decision head",
            details: {
              decision_id: expected.decision_id,
              expected_head: expected.to_h,
              current_head: current&.to_h
            }
          )
        )
      end

      def load_attempt_state(attempt_id)
        events = @event_store.read(
          @stream_factory.attempt(attempt_id),
          EventQueries::ATTEMPT_FOR_AGENT_CHOICE
        ).map { load_event(_1) }
        Domain::Attempts::State.reduce(events)
      end

      def load_existing_choice(choice_id)
        event = @event_store.read(
          @stream_factory.agent_choice(choice_id),
          EventQueries::AGENT_CHOICE_EXISTENCE
        ).first
        event && event_reference(event)
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def apply_event_plan_contract(plan, command:, context:)
        result = @event_plan_contract.call(
          plan:,
          command:,
          context:,
          expected_stream: @stream_factory.agent_choice(command.choice_id)
        )
        return plan if result.success?

        raise ArgumentError, "agent choice plan violates its dry-rb contract: #{result.errors.to_h.inspect}"
      end

      def persist_domain_plan(plan, command:, preparation:, caused_by:)
        recorded = plan.events.fetch(0)
        assessment = plan.events.fetch(1).assessment
        event_ids = [ preparation.recorded_event_id, preparation.accepted_event_id ]
        events = plan.events.zip(event_ids).map do |payload, event_id|
          @event_factory.build!(
            event: payload,
            event_id:,
            metadata: command_metadata(command),
            markers: event_markers(command, assessment, recorded.decision_context),
            caused_by:
          )
        end
        @event_store.append(@stream_factory.agent_choice(command.choice_id), events)
      end

      def event_markers(command, assessment, decision_context)
        markers = [
          "choice:#{command.choice_id}",
          "choice-type:#{command.choice_type}",
          "attempt:#{command.context.attempt_id}",
          "work-item:#{command.context.work_item_id}",
          "change-set:#{command.context.change_set_id}",
          "repository:#{command.context.repository_id}",
          "command:#{command.command_id}"
        ] + assessment.based_on_decisions.map { "decision:#{_1.decision_id}" }
        markers.concat(
          decision_context.document.partitions.map do |observation|
            "decision-partition:#{observation.partition.partition_id}"
          end
        )
        markers.uniq.freeze
      end

      def command_metadata(command)
        EventMetadata.new(
          command_id: command.command_id,
          actor_kind: command.actor.kind,
          actor_id: command.actor.id,
          recorded_by: "coordinator",
          policy_version: "testing-framework-resolution/v1"
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

      def context_limit(partition_count:, active_decision_count:)
        Failure(
          OutcomeError.new(
            code: :decision_context_limit_reached,
            message: "Authoritative Decision context exceeds the bounded resolver limits",
            details: {
              partition_count:,
              maximum_partition_count: MAXIMUM_PARTITIONS,
              active_decision_count:,
              maximum_active_decision_count: MAXIMUM_ACTIVE_DECISIONS
            }
          )
        )
      end
    end
  end
end
