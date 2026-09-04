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
        policy_loader: Coordinator::Write::CandidateObligations::ImpactPolicyLoader.new(event_store:),
        partition_state_loader: Coordinator::Write::Decisions::PartitionStateLoader.new(event_store:),
        candidate_state_loader: Coordinator::Write::Candidates::StateLoader.new(event_store:)
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @source_builder = source_builder
        @definition_loader = definition_loader
        @policy_loader = policy_loader
        @partition_state_loader = partition_state_loader
        @candidate_state_loader = candidate_state_loader
      end

      def from_partition(source)
        partition_event = source.payload
        partition = partition_for(partition_event)
        return unless partition
        return unless candidate_partition?(partition)

        state = @partition_state_loader.call(partition)
        return unless state.latest_event == source.reference
        heads = policy_heads(state.active_decisions, partition)
        if heads.length > 1
          raise CandidateObligationProcessRejected,
                "Candidate partition contains multiple active candidate.impact_policy heads"
        end
        return if heads.empty?

        observe(
          partition_event: source.reference,
          head: heads.sole,
          change_set_id: partition.anchor_id,
          observed_at: source.event.created_at.utc.iso8601(6)
        )
      end

      def current_for_registration(source)
        registration = source.payload
        candidate = @candidate_state_loader.call(registration.candidate_id)
        unless candidate&.surface_assignment_event == source.reference
          raise CandidateObligationProcessRejected,
                "Candidate impact assignment is not the Candidate's exact current surface"
        end
        change_set_id = candidate.change_set_id
        partition = expected_partition(change_set_id)
        state = @partition_state_loader.call(partition)
        return unless state.latest_event

        heads = policy_heads(state.active_decisions, partition)
        if heads.length > 1
          raise CandidateObligationProcessRejected,
                "Candidate partition contains multiple active candidate.impact_policy heads"
        end
        return if heads.empty?

        observe(
          partition_event: state.latest_event,
          head: heads.sole,
          change_set_id:,
          observed_at: source.event.created_at.utc.iso8601(6)
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

      def policy_heads(heads, partition)
        heads.select do |head|
          policy_head?(head, partition)
        end
      end

      def partition_for(event)
        return event.partition if event.is_a?(Coordinator::Write::Events::DecisionPartitionAdvancedV1)
        return unless event.is_a?(Coordinator::Write::Events::DecisionAddedToPartitionV1) ||
                      event.is_a?(Coordinator::Write::Events::DecisionRemovedFromPartitionV1)
        return unless event.partition_id.start_with?("changeset:") && event.partition_id.end_with?(":candidate")

        change_set_id = event.partition_id.delete_prefix("changeset:").delete_suffix(":candidate")
        expected_partition(change_set_id)
      end

      def expected_partition(change_set_id)
        Coordinator::Write::Decisions::DecisionPartitionV1.new(
          partition_id: "changeset:#{change_set_id}:candidate",
          topic_root: "candidate",
          anchor_kind: "changeset",
          anchor_id: change_set_id
        )
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
