# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    module OutcomeV3
      class Completed < Value
      end

      class Failed < Value
        attribute :code, Types::Identifier
        attribute :reason, Types::TaskFailureReason
        attribute :retryable, Types::Strict::Bool
      end

      Type = Completed | Failed
    end
  end
end
