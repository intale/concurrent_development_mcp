# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class AgentChoiceImpactScanCheckpointSource < Dry::Validation::Contract
      params do
        required(:state).value(Types.Instance(Coordinator::Write::Domain::AgentChoiceImpacts::ScanState))
        required(:source).value(Types.Instance(AgentChoiceImpacts::SourceV1))
      end

      rule(:state, :source) do
        state = values[:state]
        source = values[:source]
        payload = source.payload
        checkpoint_payload = payload.is_a?(Coordinator::Write::Events::AgentChoiceImpactScanStartedV1) ||
                             payload.is_a?(Coordinator::Write::Events::AgentChoiceImpactScanProgressedV1)
        complete_state = state.scan_id && state.decision_change && state.started_event &&
                         state.checkpoint_event && !state.from_position.nil? && state.to_position &&
                         state.page_size && state.policy_version
        exact_source = state.checkpoint_event == source.reference &&
                       state.scan_id == source.reference.stream_id &&
                       payload.respond_to?(:scan_id) && payload.scan_id == state.scan_id

        key(:state).failure("must be a complete running impact scan") unless state.running? && complete_state
        key(:source).failure("must be the exact current scan checkpoint") unless checkpoint_payload && exact_source
        if complete_state && (state.from_position > state.to_position || state.page_size != 50)
          key(:state).failure("must retain the frozen bounded page coordinates")
        end
      end
    end
  end
end
