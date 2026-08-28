# frozen_string_literal: true

module Coordinator::Read
  class OperationBatchItem < ApplicationRecord
    belongs_to :operation_batch,
               class_name: "Coordinator::Read::OperationBatch",
               foreign_key: "batch_id",
               inverse_of: :items
  end
end
