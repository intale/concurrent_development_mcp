# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    module OutcomeV2
      class Completed < Value
        attribute :result, SemanticResultV1::Type
      end

      class Failed < Value
        attribute :error, JsonRpcErrorV1
      end

      Type = Completed | Failed
    end
  end
end
