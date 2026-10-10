# frozen_string_literal: true

module Coordinator::Read::Search
  class ExpressionValidator
    # Conservative pg_trgm LIKE eligibility; padded equality/prefix trigrams
    # can sometimes support shorter words, but we do not admit those anchors.
    ANCHOR = /[[:alnum:]]{3}/

    def initialize(contract: ExpressionNodeContract.new)
      @contract = contract
    end

    def call(input)
      stack = [ [ input, [], 1 ] ]
      issues = []
      count = 0
      while (item = stack.pop)
        node, path, depth = item
        count += 1
        if count > Limits::FIELD_NODES || depth > Limits::DEPTH
          issues << ExpressionIssue.new(path:, message: "expression exceeds depth or node limit")
          break
        end
        result = @contract.call(node)
        if result.failure?
          issues << ExpressionIssue.new(path:, message: result.errors.to_h.inspect)
          next
        end
        value = result.to_h
        value.fetch(:operands, []).each_with_index do |child, index|
          stack << [ child, path + [ "operands", index ], depth + 1 ]
        end
      end
      if issues.empty?
        if input.key?(:operator) ? input[:operator] == "not" : input["operator"] == "not"
          issues << ExpressionIssue.new(path: [], message: "NOT must be an exclusion inside a positively anchored AND/OR query")
        elsif !anchored?(input)
          issues << ExpressionIssue.new(path: [], message: "every Boolean alternative requires a positive literal with three consecutive alphanumeric characters")
        end
      end
      ExpressionValidation.new(node_count: count, issues:)
    end

    private

    # Negation-normal-form interpretation visits each node once. It neither
    # constructs DNF nor duplicates subtrees for overlapping alternatives.
    def anchored?(input, negated = false)
      node = @contract.call(input).to_h
      return !negated && ANCHOR.match?(node.fetch(:value)) unless node[:operator]
      return anchored?(node.fetch(:operands).first, !negated) if node[:operator] == "not"

      operator = node.fetch(:operator)
      operator = operator == "and" ? "or" : "and" if negated
      results = node.fetch(:operands).map { anchored?(_1, negated) }
      operator == "and" ? results.any? : results.all?
    end
  end
end
