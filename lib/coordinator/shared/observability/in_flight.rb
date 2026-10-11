# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class InFlight
      def initialize
        @mutex = Mutex.new
        @entries = {}
      end

      def enter(attributes)
        token = Object.new
        @mutex.synchronize do
          (@entries[attributes] ||= {})[token] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
        token
      end

      def leave(attributes, token)
        @mutex.synchronize do
          entries = @entries[attributes]
          if entries
            entries.delete(token)
            @entries.delete(attributes) if entries.empty?
          end
        end
        nil
      end

      def oldest_age(attributes)
        @mutex.synchronize do
          started_at = @entries[attributes]&.values&.min
          started_at ? [ Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at, 0.0 ].max : 0.0
        end
      end
    end
  end
end
