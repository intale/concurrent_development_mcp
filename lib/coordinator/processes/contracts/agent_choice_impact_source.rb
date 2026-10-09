# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class AgentChoiceImpactSource < Dry::Validation::Contract
      params do
        required(:source).value(Types.Instance(AgentChoiceImpacts::SourceV1))
      end

      rule(:source) do
        source = value
        payload = source.payload
        expected_stream_id =
          case payload
          when Coordinator::Write::Events::DecisionActivatedV2,
               Coordinator::Write::Events::DecisionDefinitionCorrectedV2
            payload.decision_id
          when Coordinator::Write::Events::AgentChoiceAcceptedV2
            payload.choice_id
          when Coordinator::Write::Events::AgentChoiceImpactScanStartedV2,
               Coordinator::Write::Events::AgentChoiceImpactScanProgressedV2
            payload.scan_id
          end

        key.failure("payload identity must match the source stream") unless expected_stream_id == source.reference.stream_id
      end
    end
  end
end
