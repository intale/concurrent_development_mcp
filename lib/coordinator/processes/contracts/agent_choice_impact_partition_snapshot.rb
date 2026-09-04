# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class AgentChoiceImpactPartitionSnapshot < Dry::Validation::Contract
      params do
        required(:partition).value(Types.Instance(Coordinator::Write::Decisions::DecisionPartitionV1))
        required(:event).value(Types.Instance(PgEventstore::Event))
        required(:payload).value(Types.Instance(Coordinator::Write::Events::Base))
        required(:observation).value(Types.Instance(Coordinator::Write::DecisionContexts::PartitionObservationV1))
      end

      rule(:partition, :event, :payload, :observation) do
        partition = values[:partition]
        event = values[:event]
        payload = values[:payload]
        observation = values[:observation]
        heads = observation.active_decisions
        exact_heads = heads.all? do |head|
          head.decision_revision == head.event.stream_revision &&
            head.event.stream_context == "HumanGuidance" &&
            head.event.stream_name == "Decision" &&
            head.event.stream_id == head.decision_id
        end
        unique_and_ordered = heads.map(&:decision_id).uniq.length == heads.length &&
                             heads == heads.sort_by { _1.decision_id.b }
        valid_payload = if payload.is_a?(Coordinator::Write::Events::DecisionPartitionAdvancedV1)
          payload.partition == partition &&
            payload.partition_revision == event.stream_revision &&
            heads == payload.active_decisions
        elsif payload.is_a?(Coordinator::Write::Events::DecisionAddedToPartitionV1) ||
              payload.is_a?(Coordinator::Write::Events::DecisionRemovedFromPartitionV1)
          payload.partition_id == partition.partition_id &&
            payload.partition_revision == event.stream_revision
        else
          false
        end
        valid = %w[DecisionPartitionAdvanced DecisionAddedToPartition DecisionRemovedFromPartition].include?(event.type) &&
                event.stream&.context == "HumanGuidance" &&
                event.stream&.stream_name == "DecisionPartition" &&
                event.stream&.stream_id == partition.partition_id &&
                valid_payload &&
                observation.partition == partition &&
                observation.partition_revision == event.stream_revision &&
                exact_heads && unique_and_ordered

        key(:observation).failure("must be the exact current DecisionPartition snapshot") unless valid
      end
    end
  end
end
