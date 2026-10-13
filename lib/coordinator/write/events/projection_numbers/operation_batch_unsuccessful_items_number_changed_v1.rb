# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class OperationBatchUnsuccessfulItemsNumberChangedV1 < Coordinator::Write::Events::Base
    contract type: "OperationBatchUnsuccessfulItemsNumberChanged", version: 1

    attribute :batch_id, Coordinator::Write::Types::UuidV7
    attribute :items_number, Coordinator::Write::Types::Integer.constrained(
      gteq: 0, lteq: Coordinator::Write::Types::OPERATION_BATCH_MAXIMUM_ITEMS
    )
  end
end
