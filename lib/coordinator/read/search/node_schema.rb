# frozen_string_literal: true

module Coordinator::Read::Search
  module NodeSchema
    def self.build(depth = Limits::DEPTH)
      child = build(depth - 1) if depth > 1
      Dry::Schema.JSON do
        config.validate_keys = true
        optional(:match).filled(:string, included_in?: %w[contains starts_with ends_with equals])
        optional(:value).filled(:string, min_size?: 3, max_size?: Limits::LITERAL_CHARACTERS)
        optional(:case_sensitive).filled(:bool)
        optional(:operator).filled(:string, included_in?: %w[and or not])
        if child
          optional(:operands).value(:array, min_size?: 1, max_size?: Limits::OPERANDS).each(:hash, child)
        else
          optional(:operands).value(:array, size?: 0)
        end
      end
    end
  end
end
