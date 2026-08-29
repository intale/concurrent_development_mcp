# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextStateLoader
      TERMINAL_ATTEMPT_STATUSES = %w[abandoned completed].freeze

      def call(document)
        attributes = deep_symbolize(document)
        attributes[:attempts] = attributes.fetch(:attempts, []).map do |attempt|
          compact_terminal_attempt(attempt)
        end
        CoordContextStateV1.new(attributes)
      end

      private

      def compact_terminal_attempt(attempt)
        return attempt unless TERMINAL_ATTEMPT_STATUSES.include?(attempt[:status])

        attempt.merge(write_set: nil)
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array
          value.map { deep_symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
