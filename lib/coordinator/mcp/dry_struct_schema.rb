# frozen_string_literal: true

module Coordinator
  module Mcp
    class DryStructSchema
      def call(struct_class)
        object_from_keys(struct_class.schema.keys).merge(title: struct_class.name)
      end

      private

      def schema_for(type)
        schema_from_ast(type.to_ast)
      end

      def schema_from_ast(ast)
        tag, payload = ast

        case tag
        when :struct
          call(payload.fetch(0))
        when :schema
          object_from_key_asts(payload.fetch(0))
        when :key
          schema_from_ast(payload.fetch(2))
        when :constructor, :lax, :default, :meta
          schema_from_ast(payload.fetch(0))
        when :constrained
          apply_rules(schema_from_ast(payload.fetch(0)), payload.fetch(1))
        when :sum
          { oneOf: sum_members(ast).map { schema_from_ast(_1) } }
        when :array
          { type: "array", items: schema_from_ast(payload.fetch(0)) }
        when :hash
          { type: "object" }
        when :map
          { type: "object", additionalProperties: schema_from_ast(payload.fetch(1)) }
        when :enum
          schema_from_ast(payload.fetch(0)).merge(enum: payload.fetch(1).keys)
        when :nominal
          nominal(payload.fetch(0))
        when :any
          {}
        else
          raise KeyError, "Unsupported Dry type AST tag: #{tag.inspect}"
        end
      end

      def sum_members(ast)
        tag, payload = ast
        return [ ast ] unless tag == :sum

        sum_members(payload.fetch(0)) + sum_members(payload.fetch(1))
      end

      def object_from_keys(keys)
        properties = keys.to_h { |key| [ key.name, schema_for(key.type) ] }
        required = keys.select(&:required?).map { _1.name.to_s }

        object_schema(properties:, required:)
      end

      def object_from_key_asts(key_asts)
        properties = key_asts.to_h do |key_ast|
          _, (name, _, type_ast) = key_ast
          [ name, schema_from_ast(type_ast) ]
        end
        required = key_asts.filter_map do |key_ast|
          _, (name, required_key, _) = key_ast
          name.to_s if required_key
        end

        object_schema(properties:, required:)
      end

      def object_schema(properties:, required:)
        {
          type: "object",
          additionalProperties: false,
          properties:,
          required:
        }
      end

      def nominal(ruby_class)
        case ruby_class.name
        when "String", "Symbol", "Time", "Date", "DateTime"
          { type: "string" }
        when "Integer"
          { type: "integer" }
        when "Float", "BigDecimal"
          { type: "number" }
        when "TrueClass"
          { const: true }
        when "FalseClass"
          { const: false }
        when "NilClass"
          { type: "null" }
        when "Hash"
          { type: "object" }
        when "Array"
          { type: "array" }
        else
          {}
        end
      end

      def apply_rules(schema, rule_ast)
        predicates(rule_ast).reduce(schema) do |result, (name, arguments)|
          apply_predicate(result, name, arguments)
        end
      end

      def predicates(rule_ast)
        tag, payload = rule_ast
        return [ [ payload.fetch(0), payload.fetch(1) ] ] if tag == :predicate
        return predicates(payload.fetch(0)) + predicates(payload.fetch(1)) if tag == :and

        []
      end

      def apply_predicate(schema, name, arguments)
        value = predicate_value(arguments)

        case name
        when :format?
          schema.merge(pattern: json_pattern(value))
        when :min_size?
          schema.merge(size_keyword(schema, :minimum) => value)
        when :max_size?
          schema.merge(size_keyword(schema, :maximum) => value)
        when :size?
          keyword = size_keyword(schema, :minimum)
          schema.merge(keyword => value, keyword.to_s.sub("min", "max").to_sym => value)
        when :gteq?
          schema.merge(minimum: value)
        when :lteq?
          schema.merge(maximum: value)
        when :gt?
          schema.merge(exclusiveMinimum: value)
        when :lt?
          schema.merge(exclusiveMaximum: value)
        when :eql?
          schema.merge(const: value)
        when :included_in?
          schema.merge(enum: value.to_a)
        else
          schema
        end
      end

      def predicate_value(arguments)
        arguments.find { _1.fetch(0) != :input }&.fetch(1)
      end

      def size_keyword(schema, boundary)
        prefix = boundary == :minimum ? "min" : "max"
        suffix = case schema[:type]
        when "array" then "Items"
        when "object" then "Properties"
        else "Length"
        end
        :"#{prefix}#{suffix}"
      end

      def json_pattern(regexp)
        regexp.source.gsub("\\A", "^").gsub("\\z", "$")
      end
    end
  end
end
