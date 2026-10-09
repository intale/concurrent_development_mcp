# frozen_string_literal: true

module Coordinator::Read
  module Projections
    class CoordContextStateLoader
      def call(document)
        CoordContextStateV1.new(deep_symbolize(document))
      end

      private

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
