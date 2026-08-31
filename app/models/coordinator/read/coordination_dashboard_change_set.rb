# frozen_string_literal: true

module Coordinator::Read
  class CoordinationDashboardChangeSet < ApplicationRecord
    self.table_name = "coordination_dashboard_change_sets"
    self.primary_key = "change_set_id"

    def readonly? = true
  end
end
