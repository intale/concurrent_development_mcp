# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class AgentChoiceImpactSourceEvent < Dry::Validation::Contract
      STREAM_BY_TYPE = {
        "DecisionActivated" => [ "HumanGuidance", "Decision" ],
        "DecisionDefinitionCorrected" => [ "HumanGuidance", "Decision" ],
        "AgentChoiceAccepted" => [ "AgentGovernance", "AgentChoice" ],
        "AgentChoiceImpactScanStarted" => [ "AgentGovernance", "AgentChoiceImpactScan" ],
        "AgentChoiceImpactScanProgressed" => [ "AgentGovernance", "AgentChoiceImpactScan" ]
      }.freeze

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        event = value
        stream = event.stream
        expected_stream = STREAM_BY_TYPE[event.type]
        persisted = stream && event.stream_revision && event.stream_revision >= 0 &&
                    event.global_position && event.global_position >= 0
        valid_stream = expected_stream && stream &&
                       [ stream.context, stream.stream_name ] == expected_stream &&
                       Types::IDENTIFIER_PATTERN.match?(stream.stream_id.to_s)
        valid_schema = event.metadata["schema_version"] == 2 &&
                       Types::IDENTIFIER_PATTERN.match?(event.metadata["command_id"].to_s)
        valid_trace = Types::UUID_V7_PATTERN.match?(event.id.to_s) &&
                      Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)

        key.failure("must be a persisted AgentChoice impact process source") unless persisted && valid_stream
        key.failure("must carry a supported command schema version") unless valid_schema
        key.failure("must carry UUIDv7 event and correlation identities") unless valid_trace
      end
    end
  end
end
