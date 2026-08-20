# frozen_string_literal: true

module Coordinator
  class IdGenerator
    def uuid_v7
      SecureRandom.uuid_v7
    end
  end
end
