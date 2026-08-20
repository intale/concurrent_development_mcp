# frozen_string_literal: true

module Coordinator
  module Mcp
    module Schemas
      module_function

      def envelope
        {
          type: "object",
          additionalProperties: false,
          properties: {
            status: { type: "string" },
            summary: { type: "string" },
            command_id: nullable_string,
            receipt: nullable_string,
            context_token: nullable_string,
            data: { type: "object" },
            warnings: { type: "array", items: { type: "string" } },
            next_actions: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                properties: {
                  tool: { type: "string" },
                  arguments: { type: "object" }
                },
                required: %w[tool arguments]
              }
            },
            projection_status: nullable_string
          },
          required: %w[
            status summary command_id receipt context_token data warnings next_actions projection_status
          ]
        }
      end

      def change_set_create
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            goal: { type: "string", minLength: 1, maxLength: 4_000 },
            acceptance_criteria: string_array(min_items: 1, max_items: 100, max_length: 2_000)
          ),
          required: %w[command_id actor change_set_id goal acceptance_criteria]
        )
      end

      def work_item_create
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            work_item_id: identifier,
            repository_id: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
            goal: { type: "string", minLength: 1, maxLength: 4_000 },
            acceptance_criteria: string_array(min_items: 1, max_items: 50, max_length: 2_000)
          ),
          required: %w[command_id actor change_set_id work_item_id repository_id goal acceptance_criteria]
        )
      end

      def work_item_dependency_declare
        required_output = object_schema(
          properties: { kind: identifier, key: identifier },
          required: %w[kind key]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            dependency_id: identifier,
            producer_work_item_id: identifier,
            consumer_work_item_id: identifier,
            dependency_kind: { type: "string", enum: Types::DEPENDENCY_KINDS },
            required_output: { anyOf: [ required_output, { type: "null" } ] }
          ),
          required: %w[
            command_id actor change_set_id dependency_id producer_work_item_id
            consumer_work_item_id dependency_kind required_output
          ]
        )
      end

      def change_set_activate
        object_schema(
          properties: common_mutation_properties.merge(change_set_id: identifier),
          required: %w[command_id actor change_set_id]
        )
      end

      def work_item_acquire
        snapshot = object_schema(
          properties: {
            repository_id: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
            commit_oid: { type: "string", pattern: "^(?:[0-9a-f]{40}|[0-9a-f]{64})$" }
          },
          required: %w[repository_id commit_oid]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            base_snapshots: { type: "array", items: snapshot, maxItems: 100 }
          ),
          required: %w[command_id actor change_set_id work_item_id attempt_id base_snapshots]
        )
      end

      def operation_get
        object_schema(
          properties: {
            command_id: identifier,
            projections: {
              type: "array",
              minItems: 1,
              maxItems: 10,
              uniqueItems: true,
              items: { type: "string", enum: [ "coord_context_v1" ] }
            }
          },
          required: %w[command_id]
        )
      end

      def coord_context
        roots = %w[change_set_id work_item_id attempt_id]
        object_schema(
          properties: {
            change_set_id: nullable_identifier,
            work_item_id: nullable_identifier,
            attempt_id: nullable_identifier,
            after_command_id: nullable_identifier,
            context_token: {
              type: [ "string", "null" ],
              pattern: "^sha256:[0-9a-f]{64}$"
            }
          },
          required: [],
          one_of: roots.map { |root| { required: [ root ] } }
        )
      end

      def common_mutation_properties
        {
          command_id: identifier,
          actor: object_schema(
            properties: {
              kind: { type: "string", enum: Types::ACTOR_KINDS },
              id: identifier
            },
            required: %w[kind id]
          )
        }
      end

      def object_schema(properties:, required:, one_of: nil)
        schema = {
          type: "object",
          additionalProperties: false,
          properties:,
          required:
        }
        schema[:oneOf] = one_of if one_of
        schema
      end

      def identifier
        { type: "string", pattern: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$" }
      end

      def nullable_identifier
        identifier.merge(type: [ "string", "null" ])
      end

      def nullable_string
        { type: [ "string", "null" ] }
      end

      def string_array(min_items:, max_items:, max_length:)
        {
          type: "array",
          minItems: min_items,
          maxItems: max_items,
          uniqueItems: true,
          items: { type: "string", minLength: 1, maxLength: max_length }
        }
      end
    end
  end
end
