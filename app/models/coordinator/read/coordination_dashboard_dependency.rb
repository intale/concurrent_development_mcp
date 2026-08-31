# frozen_string_literal: true

module Coordinator::Read
  class CoordinationDashboardDependency < ApplicationRecord
    self.table_name = "coordination_dashboard_dependencies"
    self.primary_key = "dependency_id"

    def readonly? = true
  end
end
