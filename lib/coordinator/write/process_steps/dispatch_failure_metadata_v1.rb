# frozen_string_literal: true

module Coordinator::Write
  module ProcessSteps
    class DispatchFailureMetadataV1 < Value
      attribute :command_id, Types::UuidV7
      attribute :actor_kind, Types::String.enum("system")
      attribute :actor_id, Types::Identifier
      attribute :actor_authenticated, Types::Bool
      attribute :recorded_by, Types::String.enum("coordinator")
      attribute :policy_version, Types::String.enum("process-step-dispatch/v1")
      attribute :diagnostic_source, Types::String.enum("process-manager-operation")
    end
  end
end
