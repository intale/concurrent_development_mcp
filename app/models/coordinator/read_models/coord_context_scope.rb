# frozen_string_literal: true

module Coordinator
  module ReadModels
    class CoordContextScope < ApplicationRecord
      self.table_name = "coordinator_context_scopes"
      self.primary_key = nil
    end
  end
end
