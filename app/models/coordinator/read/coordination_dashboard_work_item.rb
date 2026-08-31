# frozen_string_literal: true

module Coordinator::Read
  class CoordinationDashboardWorkItem < ApplicationRecord
    self.table_name = "coordination_dashboard_work_items"
    self.primary_key = "work_item_id"

    def readonly? = true
  end
end
