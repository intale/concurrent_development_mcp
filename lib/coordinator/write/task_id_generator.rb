# frozen_string_literal: true

module Coordinator::Write
  class TaskIdGenerator
    def call
      SecureRandom.urlsafe_base64(32, false)
    end
  end
end
