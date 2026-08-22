# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    module OutcomeV1
      class Completed < Value
        attribute :result, ToolResultV1
      end

      class Failed < Value
        attribute :error, JsonRpcErrorV1
      end

      Type = Completed | Failed
    end
  end
end
