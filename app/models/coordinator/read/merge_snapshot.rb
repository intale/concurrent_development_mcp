# frozen_string_literal: true

module Coordinator::Read
  class MergeSnapshot < ApplicationRecord
    self.primary_key = "merge_snapshot_id"
  end
end
