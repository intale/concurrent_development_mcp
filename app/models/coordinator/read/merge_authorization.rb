# frozen_string_literal: true

module Coordinator::Read
  class MergeAuthorization < ApplicationRecord
    self.primary_key = "authorization_id"
  end
end
