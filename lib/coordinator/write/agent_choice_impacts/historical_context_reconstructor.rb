# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class HistoricalContextReconstructor
      MAXIMUM_HISTORICAL_HEADS = 64

      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        decision_loader: HistoricalDecisionLoader.new(event_store:),
        resolver: DecisionContexts::Resolver.new,
        context_builder: DecisionContexts::Builder.new,
        policy_evaluator: Domain::AgentChoices::PolicyEvaluator.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @decision_loader = decision_loader
        @resolver = resolver
        @context_builder = context_builder
        @policy_evaluator = policy_evaluator
      end

      def call(recorded_choice:, decision_change:)
        recorded_observations = recorded_choice.decision_context.document.partitions
        changes = partition_changes(recorded_observations, decision_change)
        before_observations = replace_observations(recorded_observations, changes, :before_observation)
        after_observations = replace_observations(recorded_observations, changes, :after_observation)
        decisions = load_historical_decisions(before_observations, after_observations)
        before_resolution = resolve(recorded_choice, before_observations, decisions, decision_change.changed_at)
        after_resolution = resolve(recorded_choice, after_observations, decisions, decision_change.changed_at)
        before_context = build_context(recorded_choice, before_observations, before_resolution, decision_change.changed_at)
        after_context = build_context(recorded_choice, after_observations, after_resolution, decision_change.changed_at)

        ReconstructionV1.new(
          before_context:,
          after_context:,
          before_evaluation: evaluate(before_resolution, recorded_choice.selected.option_id),
          after_evaluation: evaluate(after_resolution, recorded_choice.selected.option_id),
          source_advancements: changes.sort_by { _1.partition.partition_id.b }.map(&:advancement_event),
          source_already_observed: source_already_observed(changes)
        )
      end

      private

      def partition_changes(recorded_observations, decision_change)
        affected = decision_change.affected_partitions.to_h { [ _1.partition_id, _1 ] }
        relevant = recorded_observations.select { affected.key?(_1.partition.partition_id) }
        if relevant.empty?
          invalid!(
            "no_affected_choice_partitions",
            choice_partitions: recorded_observations.map { _1.partition.partition_id },
            source_partitions: affected.keys.sort_by(&:b)
          )
        end

        relevant.map do |recorded|
          partition = affected.fetch(recorded.partition.partition_id)
          unless partition == recorded.partition
            invalid!(
              "affected_partition_definition_mismatch",
              partition_id: partition.partition_id
            )
          end
          source_event = load_source_advancement(partition, decision_change)
          PartitionChangeV1.new(
            partition:,
            recorded_observation: recorded,
            before_observation: predecessor_observation(partition, source_event),
            after_observation: observation(source_event, partition),
            advancement_event: reference(source_event)
          )
        end.freeze
      end

      def load_source_advancement(partition, decision_change)
        events = @event_store.read_marked(
          @stream_factory.decision_partition(partition.partition_id),
          MarkedEventReadCriteria.new(
            event_type: "DecisionPartitionAdvanced",
            marker: "command:#{decision_change.source_command_id}",
            maximum_count: 1,
            direction: :asc
          )
        )
        if events.empty?
          invalid!(
            "source_partition_advancement_missing",
            partition_id: partition.partition_id,
            source_command_id: decision_change.source_command_id
          )
        end

        event = events.sole
        payload = load(event)
        expected_head = Decisions::DecisionHeadV1.new(
          decision_id: decision_change.decision_id,
          decision_revision: decision_change.source_event.stream_revision,
          event: decision_change.source_event
        )
        valid = event.metadata["command_id"] == decision_change.source_command_id &&
                payload.is_a?(Events::DecisionPartitionAdvancedV1) &&
                payload.decision == expected_head &&
                payload.change_kind == decision_change.change_kind &&
                payload.advanced_at == decision_change.changed_at
        unless valid
          invalid!(
            "source_partition_advancement_invalid",
            partition_id: partition.partition_id,
            event_id: event.id
          )
        end
        validate_snapshot!(event, payload, partition)
        event
      end

      def predecessor_observation(partition, source_event)
        return empty_observation(partition) if source_event.stream_revision.zero?

        predecessor = @event_store.read_at(
          @stream_factory.decision_partition(partition.partition_id),
          source_event.stream_revision - 1
        )
        unless predecessor
          invalid!(
            "source_partition_predecessor_missing",
            partition_id: partition.partition_id,
            source_revision: source_event.stream_revision
          )
        end
        observation(predecessor, partition)
      end

      def observation(event, partition)
        payload = load(event)
        validate_snapshot!(event, payload, partition)
        DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: event.stream_revision,
          event: reference(event),
          active_decisions: payload.active_decisions
        )
      end

      def validate_snapshot!(event, payload, partition)
        heads = payload.is_a?(Events::DecisionPartitionAdvancedV1) ? payload.active_decisions : []
        valid = payload.is_a?(Events::DecisionPartitionAdvancedV1) &&
                payload.partition == partition &&
                payload.partition_revision == event.stream_revision &&
                event.type == "DecisionPartitionAdvanced" &&
                event.stream.context == "HumanGuidance" &&
                event.stream.stream_name == "DecisionPartition" &&
                event.stream.stream_id == partition.partition_id &&
                heads.map(&:decision_id).uniq.length == heads.length &&
                heads == heads.sort_by { _1.decision_id.b } &&
                heads.all? { exact_head?(_1) }
        invalid!("decision_partition_snapshot_invalid", partition_id: partition.partition_id, event_id: event.id) unless valid
      end

      def exact_head?(head)
        head.decision_revision == head.event.stream_revision &&
          head.event.stream_context == "HumanGuidance" &&
          head.event.stream_name == "Decision" &&
          head.event.stream_id == head.decision_id
      end

      def empty_observation(partition)
        DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end

      def replace_observations(recorded, changes, reader)
        replacements = changes.to_h { [ _1.partition.partition_id, _1.public_send(reader) ] }
        recorded.map do |observation|
          replacements.fetch(observation.partition.partition_id, observation)
        end.freeze
      end

      def load_historical_decisions(before_observations, after_observations)
        heads = (before_observations + after_observations)
          .flat_map(&:active_decisions)
          .uniq { [ _1.decision_id, _1.event.event_id ] }
          .sort_by { [ _1.decision_id.b, _1.decision_revision, _1.event.event_id.b ] }
        if heads.length > MAXIMUM_HISTORICAL_HEADS
          invalid!(
            "historical_decision_limit_exceeded",
            head_count: heads.length,
            maximum_head_count: MAXIMUM_HISTORICAL_HEADS
          )
        end

        heads.map { @decision_loader.call(_1) }.freeze
      end

      def resolve(recorded_choice, observations, decisions, resolved_at)
        @resolver.call(
          context: recorded_choice.context,
          observations:,
          decisions:,
          resolved_at:
        )
      end

      def build_context(recorded_choice, observations, resolution, resolved_at)
        @context_builder.call(
          context: recorded_choice.context,
          observations:,
          resolution:,
          resolved_at:
        )
      end

      def evaluate(resolution, selected_option_id)
        @policy_evaluator.call(resolution:, selected_option_id:)
      end

      def source_already_observed(changes)
        observed = changes.map do |change|
          recorded_revision = change.recorded_observation.partition_revision || -1
          recorded_revision >= change.after_observation.partition_revision
        end
        return true if observed.all?
        return false if observed.none?

        invalid!(
          "mixed_source_partition_observation",
          partitions: changes.map { _1.partition.partition_id }
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
