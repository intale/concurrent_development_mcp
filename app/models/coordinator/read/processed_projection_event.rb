# frozen_string_literal: true

module Coordinator::Read
  class ProcessedProjectionEvent < ApplicationRecord
    self.primary_key = nil
  end
end
