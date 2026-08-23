# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class DecisionChangeSourceEvent < Dry::Validation::Contract
      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        source = value
        valid_stream = source.stream&.context == "HumanGuidance" &&
                       source.stream&.stream_name == "Decision" &&
                       source.stream&.stream_id
        valid_position = source.stream_revision && source.stream_revision >= 0 &&
                         source.global_position && source.global_position >= 0
        valid_schema = source.metadata["schema_version"] == 1 &&
                       source.metadata["command_id"] &&
                       Types::ACTOR_KINDS.include?(source.metadata["actor_kind"]) &&
                       Types::IDENTIFIER_PATTERN.match?(source.metadata["actor_id"].to_s)
        valid_type = %w[DecisionActivated DecisionDefinitionCorrected].include?(source.type)

        key.failure("must be a persisted Decision lifecycle event") unless valid_stream && valid_position && valid_schema && valid_type
      end
    end
  end
end
