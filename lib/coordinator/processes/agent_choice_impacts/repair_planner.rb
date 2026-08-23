# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class RepairPlanner
      MAX_HEADS = 32

      def initialize(
        event_store:,
        choice_loader: Coordinator::Write::AgentChoiceImpacts::ChoiceLoader.new(event_store:),
        partition_loader: PartitionSnapshotLoader.new(event_store:),
        source_builder: SourceBuilder.new(event_store:),
        decision_change_builder: Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:),
        stream_factory: Coordinator::Write::StreamFactory.new,
        contract: Contracts::AgentChoiceImpactRepairSource.new
      )
        @event_store = event_store
        @choice_loader = choice_loader
        @partition_loader = partition_loader
        @source_builder = source_builder
        @decision_change_builder = decision_change_builder
        @stream_factory = stream_factory
        @contract = contract
      end

      def call(source)
        verify_source!(source)
        choice = @choice_loader.call(
          choice_id: source.reference.stream_id,
          accepted_choice: source.reference
        )
        recorded_observations = choice.recorded.decision_context.document.partitions
        current_observations = recorded_observations.map do |observation|
          @partition_loader.call(observation.partition)
        end
        recorded_heads = head_map(recorded_observations, label: "recorded")
        current_heads = head_map(current_observations, label: "current")
        decision_ids = (recorded_heads.keys | current_heads.keys).sort_by(&:b)
        if decision_ids.length > MAX_HEADS
          raise AgentChoiceImpactProcessRejected,
                "AgentChoice repair exceeds #{MAX_HEADS} unique Decision heads"
        end

        targets = decision_ids.filter_map do |decision_id|
          recorded_head = recorded_heads[decision_id]
          current_head = current_heads[decision_id]
          next if recorded_head == current_head

          repair_target(decision_id, recorded_head:, current_head:)
        end
        RepairPlanV1.new(
          accepted_choice: source.event,
          accepted_choice_reference: source.reference,
          targets:
        )
      rescue Dry::Struct::Error => error
        raise AgentChoiceImpactProcessRejected, error.message
      end

      private

      def verify_source!(source)
        result = @contract.call(source:)
        return if result.success?

        raise InvalidSourceEvent, result.errors.to_h.inspect
      end

      def head_map(observations, label:)
        grouped = observations.flat_map(&:active_decisions).group_by(&:decision_id)
        grouped.to_h do |decision_id, heads|
          exact_heads = heads.uniq
          if exact_heads.length != 1
            raise AgentChoiceImpactProcessRejected,
                  "#{label} DecisionPartition snapshots disagree for #{decision_id}"
          end

          [ decision_id, exact_heads.sole ]
        end
      end

      def repair_target(decision_id, recorded_head:, current_head:)
        event = @event_store.read_grouped(
          @stream_factory.decision(decision_id),
          Coordinator::Write::EventQueries::DECISION_LATEST_IMPACT_CHANGE
        ).first
        unless event
          raise AgentChoiceImpactProcessRejected,
                "Divergent Decision #{decision_id} has no current impact lifecycle event"
        end

        source = @source_builder.call(event)
        result = @decision_change_builder.call(source.event)
        unless result.success?
          raise AgentChoiceImpactProcessRejected,
                "Divergent Decision #{decision_id} source is invalid: #{result.failure.details.inspect}"
        end
        decision_change = result.value!
        verify_latest_head!(decision_change, recorded_head:, current_head:)
        return unless decision_change.retroactivity == "active_attempts"

        RepairTargetV1.new(source_event: source.event, decision_change:)
      end

      def verify_latest_head!(decision_change, recorded_head:, current_head:)
        latest = decision_change.source_event
        valid = if current_head
          current_head.event == latest
        else
          recorded_head && recorded_head.event != latest
        end
        return if valid

        raise AgentChoiceImpactProcessRejected,
              "Divergent Decision #{decision_change.decision_id} does not match its current lifecycle head"
      end
    end
  end
end
