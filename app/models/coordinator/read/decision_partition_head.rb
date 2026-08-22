# frozen_string_literal: true

module Coordinator::Read
  class DecisionPartitionHead < ApplicationRecord
    self.primary_key = "partition_id"
  end
end
