# frozen_string_literal: true

module Coordinator::Mcp
  module ArtifactSchemas
    module_function

    def capture_result
      mutation_result(artifact_capture_data)
    end

    def classification_result
      mutation_result(artifact_classification_data)
    end

    def update_result
      mutation_result(artifact_update_data)
    end

    def operation_batch_acceptance_result
      mutation_result(operation_batch_acceptance_data)
    end

    def relation_declare_result
      mutation_result(relation_declare_data)
    end

    def get_result
      result(
        Schemas.object_schema(
          properties: { artifact: artifact_view },
          required: %w[artifact]
        )
      )
    end

    def content_get_result
      result(
        Schemas.object_schema(
          properties: { content: artifact_content },
          required: %w[content]
        )
      )
    end

    def list_result
      result(
        Schemas.object_schema(
          properties: { page: artifact_page },
          required: %w[page]
        )
      )
    end

    def relation_list_result
      result(
        Schemas.object_schema(
          properties: { page: relation_page },
          required: %w[page]
        )
      )
    end

    def locator_resolve_result
      result(
        Schemas.object_schema(
          properties: { page: locator_page },
          required: %w[page]
        )
      )
    end

    def result(success_data)
      result_with_error(success_data, domain_error)
    end

    def mutation_result(success_data)
      result_with_error(success_data, command_domain_error)
    end

    def result_with_error(success_data, error_data)
      Schemas.object_schema(
        properties: {
          status: { type: "string" },
          summary: { type: "string" },
          command_id: Schemas.nullable_string,
          receipt: Schemas.nullable_string,
          context_token: Schemas.nullable_string,
          data: { oneOf: [ success_data, error_data ] },
          warnings: { type: "array", items: { type: "string" } },
          next_actions: { type: "array", items: next_action }
        },
        required: %w[
          status summary command_id receipt context_token data warnings next_actions
        ]
      )
    end

    def domain_error
      Schemas.object_schema(
        properties: {
          code: { type: "string" },
          message: { type: "string" },
          details: { type: "object" }
        },
        required: %w[code message details]
      )
    end

    def command_domain_error
      Schemas.object_schema(
        properties: {
          code: {
            type: "string",
            enum: Coordinator::Write::Tasks::DomainErrorV1::ERROR_CODES.map(&:to_s)
          },
          message: { type: "string" },
          details: { type: "object" }
        },
        required: %w[code message details]
      )
    end

    def artifact_capture_data
      Schemas.object_schema(
        properties: {
          artifact_id: artifact_id,
          observation_id: observation_id,
          classification_revision: {
            type: "integer",
            minimum: 1,
            maximum: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
          },
          scope: text(maximum: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES),
          kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_KINDS },
          content_sha256: sha256,
          byte_size: artifact_byte_size,
          outcome: { type: "string", enum: %w[captured observed existing] },
          recorded_at: timestamp
        },
        required: %w[
          artifact_id observation_id classification_revision scope kind content_sha256
          byte_size outcome recorded_at
        ]
      )
    end

    def artifact_classification_data
      Schemas.object_schema(
        properties: {
          artifact_id: artifact_id,
          observation_id: observation_id,
          classification_revision: {
            type: "integer",
            minimum: 1,
            maximum: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
          },
          title: text(maximum: Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES),
          kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_KINDS },
          labels: {
            type: "array",
            maxItems: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT,
            items: text(maximum: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES)
          },
          outcome: { type: "string", enum: %w[corrected existing] },
          corrected_at: timestamp
        },
        required: %w[
          artifact_id observation_id classification_revision title kind labels outcome corrected_at
        ]
      )
    end

    def artifact_update_data
      Schemas.object_schema(
        properties: {
          artifact_id: artifact_id,
          resulting_stream_revision: { type: "integer", minimum: 0 },
          changed_properties: {
            type: "array",
            uniqueItems: true,
            items: { type: "string", enum: %w[scope title kind labels content source] }
          },
          outcome: { type: "string", enum: %w[updated existing] },
          updated_at: timestamp
        },
        required: %w[artifact_id resulting_stream_revision changed_properties outcome updated_at]
      )
    end

    def operation_batch_acceptance_data
      Schemas.object_schema(
        properties: {
          batch_id: uuid_v7,
          target_tool: {
            type: "string",
            enum: %w[development_artifact_capture development_artifact_relation_declare]
          },
          total: {
            type: "integer",
            minimum: 1,
            maximum: Types::OPERATION_BATCH_MAXIMUM_ITEMS
          },
          status: { type: "string", const: "accepted" }
        },
        required: %w[batch_id target_tool total status]
      )
    end

    def relation_declare_data
      Schemas.object_schema(
        properties: {
          relation_id: relation_id,
          source_artifact_id: artifact_id,
          relation: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS },
          target: relation_target,
          superseded_relation_id: nullable(relation_id),
          outcome: { type: "string", enum: %w[declared existing superseded] },
          declared_at: timestamp,
          superseded_at: nullable(timestamp)
        },
        required: %w[
          relation_id source_artifact_id relation target superseded_relation_id outcome
          declared_at superseded_at
        ]
      )
    end

    def artifact_view
      Schemas.object_schema(
        properties: {
          artifact: artifact_summary,
          relationships: {
            type: "array",
            maxItems: Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT,
            items: relation
          }
        },
        required: %w[artifact relationships]
      )
    end

    def artifact_summary
      Schemas.object_schema(
        properties: {
          artifact_id: artifact_id,
          stream_revision: { type: "integer", minimum: 0 },
          observation_id: observation_id,
          scope: text(maximum: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES),
          title: text(maximum: Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES),
          kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_KINDS },
          labels: {
            type: "array",
            maxItems: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT,
            items: text(maximum: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES)
          },
          media_type: { type: "string" },
          encoding: { type: "string", enum: %w[utf-8 binary] },
          content_sha256: sha256,
          byte_size: artifact_byte_size,
          source: provenance,
          classification_revision: {
            type: "integer",
            minimum: 1,
            maximum: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS
          },
          classification_reason: nullable({ type: "string", maxLength: 1_000 }),
          relationship_count: { type: "integer", minimum: 0 },
          relationship_capacity: relationship_capacity,
          captured: event_evidence,
          observed: event_evidence,
          classified: event_evidence
        },
        required: %w[
          artifact_id stream_revision observation_id scope title kind labels media_type encoding content_sha256
          byte_size source classification_revision classification_reason relationship_count
          relationship_capacity
          captured observed classified
        ]
      )
    end

    def provenance
      Schemas.object_schema(
        properties: {
          kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS },
          locator: text(maximum: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES),
          revision: nullable(
            { type: "string", maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES }
          ),
          observed_at: timestamp,
          collector: text(maximum: Types::DEVELOPMENT_ARTIFACT_COLLECTOR_MAXIMUM_BYTES)
        },
        required: %w[kind locator revision observed_at collector]
      )
    end

    def artifact_content
      common = {
        artifact_id: artifact_id,
        media_type: { type: "string" },
        content_sha256: sha256,
        byte_size: artifact_byte_size
      }
      {
        oneOf: [
          Schemas.object_schema(
            properties: common.merge(
              encoding: { type: "string", const: "utf-8" },
              text: { type: "string" }
            ),
            required: %w[artifact_id encoding media_type text content_sha256 byte_size]
          ),
          Schemas.object_schema(
            properties: common.merge(
              encoding: { type: "string", const: "binary" },
              base64: {
                type: "string",
                maxLength: Types::DEVELOPMENT_ARTIFACT_CONTENT_BASE64_MAXIMUM_BYTES
              }
            ),
            required: %w[artifact_id encoding media_type base64 content_sha256 byte_size]
          )
        ]
      }
    end

    def artifact_page
      Schemas.object_schema(
        properties: {
          items: {
            type: "array",
            maxItems: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS,
            items: artifact_summary
          },
          next_global_position: nullable({ type: "integer", minimum: 0 }),
          has_more: { type: "boolean" }
        },
        required: %w[items next_global_position has_more]
      )
    end

    def relation
      Schemas.object_schema(
        properties: {
          relation_id: relation_id,
          source_artifact_id: artifact_id,
          relation: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS },
          display_relation: { type: "string" },
          inverse_relation: { type: "string" },
          transitive: { type: "boolean" },
          supersedable: { type: "boolean" },
          target: relation_target,
          attributes: relation_attributes,
          direction: { type: "string", enum: %w[incoming outgoing] },
          peer_kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS },
          peer_id: text(maximum: Types::DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES),
          peer_artifact: nullable(artifact_summary),
          status: { type: "string", enum: %w[active superseded] },
          observed_sequence: { type: "integer", minimum: 1 },
          declared: event_evidence,
          replacement_relation_id: nullable(relation_id),
          supersession_reason: nullable(
            text(maximum: Types::DEVELOPMENT_ARTIFACT_RELATION_SUPERSESSION_REASON_MAXIMUM_BYTES)
          ),
          superseded: nullable(event_evidence),
          follow_action: nullable(next_action)
        },
        required: %w[
          relation_id source_artifact_id relation display_relation inverse_relation transitive
          supersedable target attributes direction peer_kind peer_id
          peer_artifact status observed_sequence declared replacement_relation_id
          supersession_reason superseded follow_action
        ]
      )
    end

    def relation_target
      Schemas.object_schema(
        properties: {
          kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS },
          id: text(maximum: Types::DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES),
          status: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_TARGET_STATUSES },
          name: nullable(text(maximum: Types::DEVELOPMENT_ARTIFACT_TARGET_NAME_MAXIMUM_BYTES)),
          scope: nullable(text(maximum: Types::DEVELOPMENT_ARTIFACT_TARGET_SCOPE_MAXIMUM_BYTES))
        },
        required: %w[kind id status name scope]
      )
    end

    def relation_attributes
      Schemas.object_schema(
        properties: {
          path: nullable(
            text(maximum: Types::DEVELOPMENT_ARTIFACT_RELATION_PATH_MAXIMUM_BYTES)
          ),
          fragment: nullable(
            text(maximum: Types::DEVELOPMENT_ARTIFACT_RELATION_FRAGMENT_MAXIMUM_BYTES)
          ),
          normalized_locator: nullable(
            text(maximum: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES)
          )
        },
        required: %w[path fragment normalized_locator]
      )
    end

    def relationship_capacity
      Schemas.object_schema(
        properties: {
          active_count: { type: "integer", minimum: 0 },
          active_limit: { type: "integer", minimum: 1 },
          active_remaining: { type: "integer", minimum: 0 },
          lifetime_count: { type: "integer", minimum: 0 },
          lifetime_limit: { type: "integer", minimum: 1 },
          lifetime_remaining: { type: "integer", minimum: 0 }
        },
        required: %w[
          active_count active_limit active_remaining lifetime_count lifetime_limit
          lifetime_remaining
        ]
      )
    end

    def relation_page
      Schemas.object_schema(
        properties: {
          artifact: nullable(artifact_summary),
          items: {
            type: "array",
            maxItems: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS,
            items: relation
          },
          continuation_cursor: relation_cursor,
          has_more: { type: "boolean" }
        },
        required: %w[artifact items continuation_cursor has_more]
      )
    end

    def relation_cursor
      Schemas.object_schema(
        properties: {
          after_observed_sequence: { type: "integer", minimum: 0 },
          through_observed_sequence: nullable({ type: "integer", minimum: 0 }),
          after_declared_global_position: nullable({ type: "integer", minimum: 0 }),
          after_relation_id: nullable(relation_id)
        },
        required: %w[
          after_observed_sequence through_observed_sequence
          after_declared_global_position after_relation_id
        ]
      )
    end

    def locator_page
      Schemas.object_schema(
        properties: {
          resolution: { type: "string", enum: %w[absent unique ambiguous] },
          items: {
            type: "array",
            maxItems: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS,
            items: artifact_summary
          },
          continuation_cursor: locator_cursor,
          has_more: { type: "boolean" }
        },
        required: %w[resolution items continuation_cursor has_more]
      )
    end

    def locator_cursor
      Schemas.object_schema(
        properties: {
          after_observed_sequence: { type: "integer", minimum: 0 },
          through_observed_sequence: nullable({ type: "integer", minimum: 0 }),
          after_current_global_position: nullable({ type: "integer", minimum: 0 }),
          after_observation_id: nullable(observation_id)
        },
        required: %w[
          after_observed_sequence through_observed_sequence
          after_current_global_position after_observation_id
        ]
      )
    end

    def event_evidence
      Schemas.object_schema(
        properties: {
          event: event_reference,
          actor: actor,
          markers: { type: "array", maxItems: 100, items: { type: "string" } },
          metadata: { type: "object" },
          global_position: { type: "integer", minimum: 0 },
          occurred_at: timestamp,
          persisted_at: timestamp,
          causation_id: nullable(uuid_v7),
          correlation_id: nullable(uuid_v7)
        },
        required: %w[
          event actor markers metadata global_position occurred_at persisted_at
          causation_id correlation_id
        ]
      )
    end

    def event_reference
      Schemas.object_schema(
        properties: {
          event_id: uuid_v7,
          type: Schemas.identifier,
          stream_context: Schemas.identifier,
          stream_name: Schemas.identifier,
          stream_id: Schemas.identifier,
          stream_revision: { type: "integer", minimum: 0 }
        },
        required: %w[
          event_id type stream_context stream_name stream_id stream_revision
        ]
      )
    end

    def actor
      Schemas.object_schema(
        properties: {
          kind: { type: "string", enum: Types::ACTOR_KINDS },
          id: Schemas.identifier,
          authenticated: { type: "boolean" }
        },
        required: %w[kind id authenticated]
      )
    end

    def next_action
      {
        oneOf: [
          action("development_artifact_get", artifact_arguments),
          action("development_artifact_content_get", artifact_arguments),
          action("development_artifact_locator_resolve", locator_arguments),
          action("coord_context", coordination_arguments),
          action("candidate_get", identifier_arguments(:candidate_id)),
          action("decision_get", identifier_arguments(:decision_id)),
          action("skill_get", skill_arguments),
          action("repository_list", repository_arguments),
          action("operation_batch_get", operation_batch_arguments)
        ]
      }
    end

    def action(tool, arguments)
      Schemas.object_schema(
        properties: {
          tool: { type: "string", const: tool },
          arguments:
        },
        required: %w[tool arguments]
      )
    end

    def artifact_arguments
      Schemas.object_schema(
        properties: {
          artifact_id: artifact_id,
          observation_id: nullable(observation_id)
        },
        required: %w[artifact_id]
      )
    end

    def operation_batch_arguments
      Schemas.object_schema(
        properties: { batch_id: uuid_v7 },
        required: %w[batch_id]
      )
    end

    def coordination_arguments
      Schemas.object_schema(
        properties: {
          change_set_id: Schemas.identifier,
          work_item_id: Schemas.identifier,
          attempt_id: Schemas.identifier
        },
        required: [],
        one_of: %w[change_set_id work_item_id attempt_id].map { { required: [ _1 ] } }
      )
    end

    def identifier_arguments(name)
      Schemas.object_schema(
        properties: { name => Schemas.identifier },
        required: [ name.to_s ]
      )
    end

    def skill_arguments
      Schemas.object_schema(
        properties: {
          name: text(maximum: Types::SKILL_NAME_MAXIMUM_BYTES),
          scope: text(maximum: Types::SKILL_SCOPE_MAXIMUM_BYTES)
        },
        required: %w[name scope]
      )
    end

    def repository_arguments
      Schemas.object_schema(
        properties: {
          scope: text(maximum: Types::DEVELOPMENT_ARTIFACT_TARGET_SCOPE_MAXIMUM_BYTES),
          repository_key: Schemas.identifier
        },
        required: %w[scope repository_key]
      )
    end

    def locator_arguments
      Schemas.object_schema(
        properties: {
          scope: text(maximum: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES),
          source_kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS },
          locator: text(maximum: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES),
          source_revision: nullable(
            { type: "string", maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES }
          ),
          cursor: locator_cursor,
          limit: {
            type: "integer",
            minimum: 1,
            maximum: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
          }
        },
        required: %w[scope source_kind locator cursor limit]
      )
    end

    def artifact_id
      Schemas.identifier
    end

    def observation_id
      Schemas.identifier
    end

    def relation_id
      Schemas.identifier
    end

    def artifact_byte_size
      {
        type: "integer",
        minimum: 0,
        maximum: Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES
      }
    end

    def text(maximum:)
      { type: "string", minLength: 1, maxLength: maximum }
    end

    def sha256
      { type: "string", pattern: "^sha256:[0-9a-f]{64}$" }
    end

    def timestamp
      {
        type: "string",
        pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
      }
    end

    def uuid_v7
      Schemas.uuid_v7
    end

    def nullable(schema)
      { anyOf: [ schema, { type: "null" } ] }
    end
  end
end
