# frozen_string_literal: true

module Coordinator::Shared
  class SystemClock
    def now
      Time.now.utc.iso8601(6)
    end
  end
end
