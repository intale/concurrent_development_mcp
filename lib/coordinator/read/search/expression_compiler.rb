# frozen_string_literal: true

module Coordinator::Read::Search
  class ExpressionCompiler
    def call(node, column:, offset: 0)
      binds = []
      sql = predicate(node, column, binds, offset)
      SqlFragment.new(sql:, binds:)
    end

    def excerpt_position(node, column:, offset: 0)
      binds = []
      alternatives = positive_literals(node).map do |literal|
        condition = predicate(literal, column, binds, offset)
        binds << literal.value
        value = "$#{offset + binds.length}"
        position = literal.case_sensitive ? "strpos(#{column}, #{value})" : "strpos(lower(#{column}), lower(#{value}))"
        "WHEN #{condition} THEN GREATEST(1, #{position})"
      end
      SqlFragment.new(sql: "CASE #{alternatives.join(' ')} ELSE 1 END", binds:)
    end

    private

    def predicate(node, column, binds, offset)
      if node.operator
        children = node.operands.map { predicate(_1, column, binds, offset) }
        return "(NOT #{children.first})" if node.operator == "not"

        return "(#{children.join(node.operator == 'and' ? ' AND ' : ' OR ')})"
      end
      value = node.value
      if node.match == "equals" && node.case_sensitive
        binds << value
        return "#{column} = $#{offset + binds.length}"
      end
      escaped = value.gsub(/[\\%_]/) { "\\#{_1}" }
      pattern = case node.match
      when "contains" then "%#{escaped}%"
      when "starts_with" then "#{escaped}%"
      when "ends_with" then "%#{escaped}"
      else escaped
      end
      binds << pattern
      "#{column} #{node.case_sensitive ? 'LIKE' : 'ILIKE'} $#{offset + binds.length} ESCAPE E'\\\\'"
    end

    def positive_literals(node, negated = false)
      return negated ? [] : [ node ] unless node.operator
      return positive_literals(node.operands.first, !negated) if node.operator == "not"

      node.operands.flat_map { positive_literals(_1, negated) }
    end
  end
end
