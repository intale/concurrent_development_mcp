# frozen_string_literal: true

module Coordinator::Shared
  class IdGenerator
    def uuid_v7
      SecureRandom.uuid_v7.encode(Encoding::UTF_8)
    end
  end
end
