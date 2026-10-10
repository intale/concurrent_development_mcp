# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class AssignmentV1 < Value
      attribute :item, ItemV2
      attribute :event, Types.Instance(PgEventstore::Event)

      def assigned?
        event.type == "OperationBatchItemCommandAssigned"
      end
    end
  end
end
