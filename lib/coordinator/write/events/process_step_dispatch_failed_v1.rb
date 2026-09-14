# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ProcessStepDispatchFailedV1 < Base
      contract type: "ProcessStepDispatchFailed", version: 1

      attribute :process_step_id, Types::UuidV7
      attribute :target_command_id, Types::UuidV7
      attribute :code, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :retryable, Types::Strict::Bool
    end
  end
end
