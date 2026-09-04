# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class AgentChoiceImpactRepairSource < Dry::Validation::Contract
      params do
        required(:source).value(Types.Instance(AgentChoiceImpacts::SourceV1))
      end

      rule(:source) do
        source = value
        payload = source.payload
        valid = (payload.is_a?(Coordinator::Write::Events::AgentChoiceAcceptedV1) ||
                 payload.is_a?(Coordinator::Write::Events::AgentChoiceAcceptedV2)) &&
                source.reference.type == "AgentChoiceAccepted" &&
                source.reference.stream_context == "AgentGovernance" &&
                source.reference.stream_name == "AgentChoice" &&
                source.reference.stream_revision == 1 &&
                payload.choice_id == source.reference.stream_id

        key.failure("must be an exact accepted Choice source") unless valid
      end
    end
  end
end
