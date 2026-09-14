# frozen_string_literal: true

module Coordinator::Read
  class ResourceWorkIntentionBrowserRow < ApplicationRecord
    self.table_name = "resource_work_intention_browser_rows"
    self.primary_key = "intention_id"

    def readonly? = true
  end
end
