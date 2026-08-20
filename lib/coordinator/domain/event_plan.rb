# frozen_string_literal: true

module Coordinator
  module Domain
    class EventPlan < Value
      Write = Types.Instance(EventWrite)

      attribute :writes, Types::Array.of(Write).constrained(min_size: 1)

      def events
        writes.map(&:event).freeze
      end
    end
  end
end
