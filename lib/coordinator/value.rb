# frozen_string_literal: true

module Coordinator
  class Value < Dry::Struct
    schema schema.strict

    def initialize(attributes)
      super(deep_duplicate(attributes))

      self.class.attribute_names.each { |name| deep_freeze(public_send(name)) }
      freeze
    end

    private

    def deep_duplicate(value)
      case value
      when String
        value.dup
      when Array
        value.map { |element| deep_duplicate(element) }
      when Hash
        value.to_h { |key, element| [ deep_duplicate(key), deep_duplicate(element) ] }
      else
        value
      end
    end

    def deep_freeze(value)
      case value
      when Array
        value.each { |element| deep_freeze(element) }
      when Hash
        value.each { |key, element| deep_freeze(key); deep_freeze(element) }
      end

      value.freeze
    end
  end
end
