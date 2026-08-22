# frozen_string_literal: true

module Coordinator::Read
  class CoordContext < ApplicationRecord
    self.table_name = "coordinator_contexts"
    self.primary_key = "change_set_id"
  end
end
