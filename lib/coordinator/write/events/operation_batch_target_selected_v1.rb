# frozen_string_literal: true

module Coordinator::Write
  module Events
    class OperationBatchTargetSelectedV1 < Base
      contract type: "OperationBatchTargetSelected", version: 1

      attribute :batch_id, Types::OperationBatchId
      attribute :target_tool, Types::OperationBatchTargetTool
    end
  end
end
