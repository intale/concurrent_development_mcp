# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSet < ApplicationRecord
    self.primary_key = "release_set_id"
  end
end
