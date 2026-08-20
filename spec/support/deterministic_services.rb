# frozen_string_literal: true

module TestSupport
  class DeterministicIdGenerator
    def initialize
      @sequence = 0
    end

    def uuid_v7
      @sequence += 1
      format("018fd0f0-0000-7000-8000-%012x", @sequence)
    end
  end

  class FixedClock
    def initialize(now)
      @now = now
    end

    attr_reader :now
  end
end
