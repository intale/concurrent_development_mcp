# frozen_string_literal: true

module Coordinator::Read
  class OperationBatch < ApplicationRecord
    self.primary_key = "batch_id"

    has_many :outcomes,
             class_name: "Coordinator::Read::OperationBatchOutcome",
             foreign_key: "batch_id",
             inverse_of: :operation_batch,
             dependent: :delete_all

    has_many :items,
             class_name: "Coordinator::Read::OperationBatchItem",
             foreign_key: "batch_id",
             inverse_of: :operation_batch,
             dependent: :delete_all
  end
end
