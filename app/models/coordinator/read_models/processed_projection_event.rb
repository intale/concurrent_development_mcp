# frozen_string_literal: true

module Coordinator
  module ReadModels
    class ProcessedProjectionEvent < ApplicationRecord
      self.primary_key = nil
    end
  end
end
