# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class PolicyObserver
      TOPIC_ID = "candidate.impact_policy"

      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        source_builder: SourceBuilder.new(event_store:),
        definition_loader: Coordinator::Write::CandidateObligations::DecisionDefinitionLoader.new(event_store:),
        policy_loader: Coordinator::Write::CandidateObligations::ImpactPolicyLoader.new(event_store:)
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @source_builder = source_builder
        @definition_loader = definition_loader
        @policy_loader = policy_loader
      end

      def from_partition(source)
        partition_event = source.payload
        partition = partition_event.partition
        return unless candidate_partition?(partition)
        return unless policy_head?(partition_event.decision, partition)

        observe(
          partition_event: source.reference,
          head: partition_event.decision,
          change_set_id: partition.anchor_id,
          observed_at: partition_event.advanced_at
        )
      end

      def current_for_registration(source)
        registration = source.payload
        change_set_id = registration.change_set_id
        event = @event_store.read_grouped(
          @stream_factory.decision_partition("changeset:#{change_set_id}:candidate"),
          Coordinator::Write::EventQueries::DECISION_PARTITION_LATEST
        ).first
        return unless event

        partition_source = @source_builder.call(event)
        partition_event = partition_source.payload
        return unless candidate_partition?(partition_event.partition, change_set_id:)

        heads = partition_event.active_decisions.select do |head|
          policy_head?(head, partition_event.partition)
        end
        if heads.length > 1
          raise CandidateObligationProcessRejected,
                "Candidate partition contains multiple active candidate.impact_policy heads"
        end
        return if heads.empty?

        observe(
          partition_event: partition_source.reference,
          head: heads.sole,
          change_set_id:,
          observed_at: registration.registered_at
        )
      rescue Coordinator::Write::CandidateObligations::InvalidHistory => error
        raise CandidateObligationProcessRejected, error.message
      end

      private

      def candidate_partition?(partition, change_set_id: partition.anchor_id)
        partition.topic_root == "candidate" &&
          partition.anchor_kind == "changeset" &&
          partition.anchor_id == change_set_id &&
          partition.partition_id == "changeset:#{change_set_id}:candidate"
      end

      def policy_head?(head, partition)
        definition = @definition_loader.call(head:, partition:)
        definition.document.topic.topic_id == TOPIC_ID
      end

      def observe(partition_event:, head:, change_set_id:, observed_at:)
        observation = @policy_loader.call(
          policy_partition_event: partition_event,
          policy_head: head,
          change_set_id:,
          observed_at:
        )
        return unless observation.status == "gating"

        PolicyTriggerV1.new(
          change_set_id:,
          partition_event:,
          head:
        )
      end
    end
  end
end
