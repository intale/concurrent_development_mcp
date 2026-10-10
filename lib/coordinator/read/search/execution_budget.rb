# frozen_string_literal: true

module Coordinator::Read::Search
  class ExecutionBudget
    class Exceeded < StandardError; end

    def initialize
      @deadline = now + Limits::REQUEST_MILLISECONDS / 1000.0
    end

    def statement_milliseconds
      remaining = ((@deadline - now) * 1000).floor
      raise Exceeded, "Development search execution budget exceeded; narrow the query and retry" unless remaining.positive?

      [ remaining, Limits::STATEMENT_MILLISECONDS ].min
    end

    def check!
      statement_milliseconds
      nil
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
