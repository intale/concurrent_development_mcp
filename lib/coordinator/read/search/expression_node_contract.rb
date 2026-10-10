# frozen_string_literal: true

module Coordinator::Read::Search
  class ExpressionNodeContract < Dry::Validation::Contract
    config.validate_keys = true

    schema(NodeSchema.build)

    rule do
      if values.key?(:operator)
        key.failure("Boolean nodes contain only operator and operands") if values.keys.any? { %i[match value case_sensitive].include?(_1) }
        key.failure("operands are required") unless values.key?(:operands)
        if values[:operands]
          count = values[:operands].length
          expected = values[:operator] == "not" ? count == 1 : count >= 2
          key.failure("NOT takes one operand; AND/OR take two or more") unless expected
        end
      else
        key.failure("literal nodes require match and value") unless values.key?(:match) && values.key?(:value)
        key.failure("literal nodes cannot contain operands") if values.key?(:operands)
      end
    end

    rule(:value) do
      next unless value

      key.failure("must be valid UTF-8 without NUL") unless value.encoding == Encoding::UTF_8 && value.valid_encoding? && !value.include?("\0")
      key.failure("must be at most #{Limits::LITERAL_BYTES} bytes") if value.bytesize > Limits::LITERAL_BYTES
    end
  end
end
