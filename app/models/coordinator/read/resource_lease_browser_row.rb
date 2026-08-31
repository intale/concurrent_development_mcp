# frozen_string_literal: true

module Coordinator::Read
  class ResourceLeaseBrowserRow < ApplicationRecord
    self.table_name = "resource_lease_browser_rows"
    self.primary_key = "lease_id"

    def readonly? = true
  end
end
