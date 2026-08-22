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
            }
          },
          required: %w[
            status summary command_id receipt context_token data warnings next_actions
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

      def write_set_reserve
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            repository_id: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
            base_commit_oid: git_oid,
            resources: {
              type: "array",
              items: write_set_resource,
              minItems: 1,
              maxItems: 32
            },
            lease_duration_seconds: { type: "integer", minimum: 30, maximum: 3_600 }
          ),
          required: %w[
            command_id actor change_set_id work_item_id attempt_id repository_id
            base_commit_oid resources lease_duration_seconds
          ]
        )
      end

      def write_set_expand
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            lease_set_id: uuid_v7,
            repository_id: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
            base_commit_oid: git_oid,
            resources: {
              type: "array",
              items: write_set_resource,
              minItems: 1,
              maxItems: 32
            }
          ),
          required: %w[
            command_id actor change_set_id work_item_id attempt_id lease_set_id
            repository_id base_commit_oid resources
          ]
        )
      end

      def lease_renew
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            lease_set_id: uuid_v7,
            leases: {
              type: "array",
              items: lease_renewal_reference,
              minItems: 1,
              maxItems: 32,
              uniqueItems: true
            },
            lease_duration_seconds: { type: "integer", minimum: 30, maximum: 3_600 }
          ),
          required: %w[
            command_id actor change_set_id work_item_id attempt_id lease_set_id
            leases lease_duration_seconds
          ]
        )
      end

      def lease_release
        object_schema(
          properties: common_mutation_properties.merge(
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            lease_set_id: uuid_v7,
            leases: {
              type: "array",
              items: lease_release_reference,
              minItems: 1,
              maxItems: 32,
              uniqueItems: true
            }
          ),
          required: %w[
            command_id actor change_set_id work_item_id attempt_id lease_set_id leases
          ]
        )
      end

      def operation_get
        object_schema(
          properties: {
            command_id: identifier
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

      def git_oid
        { type: "string", pattern: "^(?:[0-9a-f]{40}|[0-9a-f]{64})$" }
      end

      def uuid_v7
        {
          type: "string",
          pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
        }
      end

      def write_set_resource
        object_schema(
          properties: {
            kind: { type: "string", enum: [ "file" ] },
            path: { type: "string", minLength: 1, maxLength: 1_024 },
            base_blob_oid: { anyOf: [ git_oid, { type: "null" } ] }
          },
          required: %w[kind path]
        )
      end

      def lease_renewal_reference
        object_schema(
          properties: {
            resource_key_hash: {
              type: "string",
              pattern: "^sha256:[0-9a-f]{64}$"
            },
            lease_id: uuid_v7,
            fencing_token: { type: "integer", minimum: 1 }
          },
          required: %w[resource_key_hash lease_id fencing_token]
        )
      end

      def lease_release_reference
        lease_renewal_reference
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
