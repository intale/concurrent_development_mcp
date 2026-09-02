# frozen_string_literal: true

module Coordinator::Write
  module ProcessSteps
    class MetadataV1 < Value
      attribute :command_id, Types::UuidV7
      attribute :actor_kind, Types::String.enum("system")
      attribute :actor_id, Types::Identifier
      attribute :actor_authenticated, Types::Bool
      attribute :recorded_by, Types::String.enum("coordinator")
      attribute :rule_version, Types::String.constrained(min_size: 1, max_size: 200)
    end
  end
end
