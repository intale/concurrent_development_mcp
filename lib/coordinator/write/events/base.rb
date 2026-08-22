# frozen_string_literal: true

module Coordinator::Write
  module Events
    class Base < Value
      class << self
        attr_reader :event_type, :schema_version

        private

        def contract(type:, version:)
          @event_type = type.freeze
          @schema_version = version
        end
      end
    end
  end
end
