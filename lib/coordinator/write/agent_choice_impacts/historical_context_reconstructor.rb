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
        change_event = read_reference(decision_change.source_event)
        invalid!("decision_change_source_missing", source: decision_change.source_event.to_h) unless change_event
        changed_at = change_event.created_at.utc.iso8601(6)
        recorded_observations = recorded_choice.decision_context.document.partitions
        changes = cohesive_partition_changes(recorded_observations, decision_change, change_event)
        before_observations = replace_observations(recorded_observations, changes, :before_observation)
        after_observations = replace_observations(recorded_observations, changes, :after_observation)
        decisions = load_historical_decisions(before_observations, after_observations)
        before_resolution = resolve(recorded_choice, before_observations, decisions, changed_at)
        after_resolution = resolve(recorded_choice, after_observations, decisions, changed_at)
        before_context = build_context(recorded_choice, before_observations, before_resolution, changed_at)
        after_context = build_context(recorded_choice, after_observations, after_resolution, changed_at)

        ReconstructionV1.new(
          before_context:,
          after_context:,
          before_evaluation: evaluate(before_resolution, recorded_choice.selected.option_id),
          after_evaluation: evaluate(after_resolution, recorded_choice.selected.option_id),
          source_advancements: changes.sort_by { _1.partition.partition_id.b }.map(&:advancement_event).uniq,
          source_already_observed: source_already_observed(changes)
        )
      end

      private

      def cohesive_partition_changes(recorded_observations, decision_change, source_event)
        affected = decision_change.affected_partitions.to_h { [ _1.partition_id, _1 ] }
        relevant = recorded_observations.select { affected.key?(_1.partition.partition_id) }
        if relevant.empty?
          invalid!(
            "no_affected_choice_partitions",
            choice_partitions: recorded_observations.map { _1.partition.partition_id },
            source_partitions: affected.keys.sort_by(&:b)
          )
        end

        source_head = Decisions::DecisionHeadV1.new(
          decision_id: decision_change.decision_id,
          decision_revision: source_event.stream_revision,
          event: reference(source_event)
        )
        after_decision = @decision_loader.call(source_head)
        previous_event = previous_lifecycle_event(source_event)
        previous_head = previous_event && Decisions::DecisionHeadV1.new(
          decision_id: decision_change.decision_id,
          decision_revision: previous_event.stream_revision,
          event: reference(previous_event)
        )
        before_decision = previous_head && @decision_loader.call(previous_head)
        before_partition_ids = before_decision ? before_decision.partitions.map(&:partition_id) : []
        after_partition_ids = after_decision.partitions.map(&:partition_id)

        relevant.map do |recorded|
          partition = affected.fetch(recorded.partition.partition_id)
          unless partition == recorded.partition
            invalid!("affected_partition_definition_mismatch", partition_id: partition.partition_id)
          end

          baseline = recorded.active_decisions.reject do |head|
            head.decision_id == decision_change.decision_id
          end
          before_heads = baseline.dup
          before_heads << previous_head if previous_head && before_partition_ids.include?(partition.partition_id)
          after_heads = baseline.dup
          after_heads << source_head if after_partition_ids.include?(partition.partition_id)
          PartitionChangeV1.new(
            partition:,
            recorded_observation: recorded,
            before_observation: observation_with_heads(recorded, before_heads),
            after_observation: observation_with_heads(recorded, after_heads),
            advancement_event: decision_change.source_event
          )
        end.freeze
      end

      def observation_with_heads(recorded, heads)
        DecisionContexts::PartitionObservationV1.new(
          partition: recorded.partition,
          partition_revision: recorded.partition_revision,
          event: recorded.event,
          active_decisions: heads.uniq(&:decision_id).sort_by { _1.decision_id.b }
        )
      end

      def previous_lifecycle_event(source_event)
        return if source_event.stream_revision.zero?

        stream = StreamReference.new(
          context: source_event.stream.context,
          stream_name: source_event.stream.stream_name,
          stream_id: source_event.stream.stream_id
        )
        @event_store.read_latest(
          stream,
          LatestEventReadCriteria.new(
            event_types: %w[DecisionActivated DecisionDefinitionCorrected],
            from_revision: source_event.stream_revision - 1
          )
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
          decision_id = change.advancement_event.stream_id
          expected = change.after_observation.active_decisions.find { _1.decision_id == decision_id }
          recorded = change.recorded_observation.active_decisions.find { _1.decision_id == decision_id }
          expected ? recorded && recorded.decision_revision >= expected.decision_revision : recorded.nil?
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

      def read_reference(event_reference)
        event = @event_store.read_at(
          StreamReference.new(
            context: event_reference.stream_context,
            stream_name: event_reference.stream_name,
            stream_id: event_reference.stream_id
          ),
          event_reference.stream_revision
        )
        event if event && reference(event) == event_reference
      end

      def invalid!(reason, evidence)
        raise InvalidHistory.new(reason:, evidence:)
      end
    end
  end
end
