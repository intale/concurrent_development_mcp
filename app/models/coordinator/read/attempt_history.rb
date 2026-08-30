# frozen_string_literal: true

module Coordinator::Read
  class AttemptHistory < ApplicationRecord
    self.table_name = "attempt_histories"
    self.primary_key = "attempt_id"
  end
end
