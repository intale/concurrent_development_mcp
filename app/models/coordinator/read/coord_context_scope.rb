# frozen_string_literal: true

module Coordinator::Read
  class CoordContextScope < ApplicationRecord
    self.table_name = "coordinator_context_scopes"
    self.primary_key = nil
  end
end
