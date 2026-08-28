# frozen_string_literal: true

module Coordinator
  module Mcp
    module Schemas
      ACTOR_ATTRIBUTION_DESCRIPTION =
        "Caller-supplied attribution label recorded with the request; it is not authenticated identity, authorization, or a session credential."

      module_function

      def envelope(data: { type: "object" }, next_action: generic_next_action)
        {
          type: "object",
          additionalProperties: false,
          properties: {
            status: { type: "string" },
            summary: { type: "string" },
            command_id: nullable_string,
            receipt: nullable_string,
            context_token: nullable_string,
            data:,
            warnings: { type: "array", items: { type: "string" } },
            next_actions: {
              type: "array",
              items: next_action
            }
          },
          required: %w[
            status summary command_id receipt context_token data warnings next_actions
          ]
        }
      end

      def generic_next_action
        object_schema(
          properties: {
            tool: { type: "string" },
            arguments: { type: "object" }
          },
          required: %w[tool arguments]
        )
      end

      def utf8_text(maximum_bytes:, minimum_bytes: 1)
        {
          type: "string",
          minLength: minimum_bytes,
          maxLength: maximum_bytes,
          "x-encoding": "UTF-8",
          "x-maxBytes": maximum_bytes
        }
      end

      def utf8_text_array(max_items:, maximum_bytes:)
        {
          type: "array",
          minItems: 0,
          maxItems: max_items,
          uniqueItems: true,
          items: utf8_text(maximum_bytes:)
        }
      end

      def repository_register
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            repository_id: uuid_v7.merge(
              description: "Caller-created Repository UUID proposal; the server returns the canonical UUID already bound to the exact scope and key when one exists."
            ),
            scope: utf8_text(maximum_bytes: 500).merge(
              description: "Exact project/workspace coordination scope; the server infers no hierarchy."
            ),
            repository_key: identifier.merge(
              description: "Exact case-sensitive caller/user-chosen logical key within scope; no filesystem location is inferred."
            ),
            display_name: { anyOf: [ utf8_text(maximum_bytes: 255), { type: "null" } ] },
            paths: utf8_text_array(max_items: 20, maximum_bytes: 1_024),
            remotes: utf8_text_array(max_items: 20, maximum_bytes: 2_048)
          ),
          required: %w[command_id actor repository_id scope repository_key display_name paths remotes]
        )
      end

      def repository_list
        object_schema(
          properties: {
            scope: {
              type: "string",
              minLength: 1,
              maxLength: 500,
              description: "Exact caller/user-chosen coordination scope; no hierarchy or fallback is inferred."
            },
            repository_key: identifier.merge(
              description: "Optional exact logical key filter within scope; matching is case-sensitive."
            ),
            after_repository_id: {
              anyOf: [ uuid_v7, { type: "null" } ],
              description: "Exclusive canonical Repository-ID cursor returned by the previous page."
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: %w[scope]
        )
      end

      def coordination_list
        cursor = object_schema(
          properties: {
            through_last_processed_at: canonical_timestamp,
            after_last_processed_at: canonical_timestamp,
            after_change_set_id: identifier
          },
          required: %w[through_last_processed_at after_last_processed_at after_change_set_id]
        )
        object_schema(
          properties: {
            scope: {
              type: "string",
              minLength: 1,
              maxLength: 500,
              description: "Exact project/workspace scope; the server infers no hierarchy or fallback."
            },
            repository_id: { anyOf: [ uuid_v7, { type: "null" } ] },
            statuses: {
              type: "array",
              minItems: 1,
              maxItems: 3,
              uniqueItems: true,
              items: { type: "string", enum: %w[planning active completed] }
            },
            cursor: { anyOf: [ cursor, { type: "null" } ] },
            limit: {
              anyOf: [
                {
                  type: "integer",
                  minimum: 1,
                  maximum: Types::COORDINATION_DISCOVERY_MAXIMUM_ITEMS
                },
                { type: "null" }
              ]
            }
          },
          required: %w[scope]
        )
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
            repository_id: uuid_v7,
            goal: { type: "string", minLength: 1, maxLength: 4_000 },
            acceptance_criteria: string_array(min_items: 1, max_items: 50, max_length: 2_000)
          ),
          required: %w[command_id actor change_set_id work_item_id repository_id goal acceptance_criteria]
        )
      end

      def work_item_dependency_declare
        required_output = object_schema(
          properties: {
            kind: { type: "string", enum: Types::DEPENDENCY_REQUIRED_OUTPUT_KINDS },
            key: identifier
          },
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
            repository_id: uuid_v7,
            commit_oid: { type: "string", pattern: "^(?:[0-9a-f]{40}|[0-9a-f]{64})$" }
          },
          required: %w[repository_id commit_oid]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            base_snapshots: { type: "array", items: snapshot, maxItems: 100 }
          ),
          required: %w[command_id actor change_set_id work_item_id attempt_id base_snapshots]
        )
      end

      def work_item_complete
        output = object_schema(
          properties: {
            kind: { type: "string", enum: Types::WORK_ITEM_OUTPUT_KINDS },
            key: identifier
          },
          required: %w[kind key]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            candidate_id: identifier,
            produced_outputs: {
              type: "array",
              items: output,
              maxItems: Types::WORK_ITEM_OUTPUT_MAXIMUM_COUNT,
              uniqueItems: true
            }
          ),
          required: %w[
            command_id actor change_set_id work_item_id attempt_id candidate_id produced_outputs
          ]
        )
      end

      def attempt_abandon
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            reason: {
              type: "string",
              minLength: 1,
              maxLength: 2_000
            }
          ),
          required: %w[command_id actor change_set_id work_item_id attempt_id reason]
        )
      end

      def write_set_reserve
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            repository_id: uuid_v7,
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
            actor: agent_actor,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            lease_set_id: uuid_v7,
            repository_id: uuid_v7,
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
            actor: agent_actor,
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
            actor: agent_actor,
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

      def guidance_record
        anchors = object_schema(
          properties: {
            repository_ids: {
              type: "array",
              items: uuid_v7,
              maxItems: 100,
              uniqueItems: true
            },
            change_set_id: nullable_identifier,
            work_item_id: nullable_identifier,
            attempt_id: nullable_identifier
          },
          required: %w[repository_ids change_set_id work_item_id attempt_id]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            message_id: identifier,
            conversation_id: identifier,
            source: { type: "string", enum: Types::GUIDANCE_SOURCES },
            text: { type: "string", minLength: 1, maxLength: 16_000 },
            anchors:
          ),
          required: %w[command_id actor message_id conversation_id source text anchors]
        )
      end

      def decision_interpretation_propose
        object_schema(
          properties: common_mutation_properties.merge(
            interpretation_id: identifier,
            source_message_id: identifier,
            source_span: {
              anyOf: [ interpretation_source_span, { type: "null" } ]
            },
            classifier: interpretation_classifier,
            proposed_decision: interpretation_decision,
            ambiguities: {
              type: "array",
              maxItems: 20,
              items: interpretation_ambiguity
            }
          ),
          required: %w[
            command_id actor interpretation_id source_message_id source_span
            classifier proposed_decision ambiguities
          ]
        )
      end

      def decision_interpretation_adjudicate
        rationale = object_schema(
          properties: {
            code: identifier,
            summary: { type: "string", minLength: 1, maxLength: 500 }
          },
          required: %w[code summary]
        )
        clarification = object_schema(
          properties: {
            status: { type: "string", enum: Types::INTERPRETATION_CLARIFICATION_STATUSES },
            questions: {
              type: "array",
              minItems: 1,
              maxItems: 20,
              uniqueItems: true,
              items: interpretation_question
            }
          },
          required: %w[status questions]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            source_message_id: identifier,
            interpretation_id: identifier,
            action: { type: "string", enum: Types::INTERPRETATION_ADJUDICATION_ACTIONS },
            rationale:,
            clarification: { anyOf: [ clarification, { type: "null" } ] }
          ),
          required: %w[
            command_id actor source_message_id interpretation_id action rationale clarification
          ]
        )
      end

      def decision_activate
        rationale = object_schema(
          properties: {
            code: identifier,
            summary: { type: "string", minLength: 1, maxLength: 500 }
          },
          required: %w[code summary]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            decision_id: identifier,
            interpretation_id: identifier,
            rationale:
          ),
          required: %w[command_id actor decision_id interpretation_id rationale]
        )
      end

      def decision_correct
        expected_head = object_schema(
          properties: {
            event_id: uuid_v7,
            type: { type: "string", enum: %w[DecisionActivated DecisionDefinitionCorrected] },
            stream_context: { type: "string", const: "HumanGuidance" },
            stream_name: { type: "string", const: "Decision" },
            stream_id: identifier,
            stream_revision: { type: "integer", minimum: 0 }
          },
          required: %w[event_id type stream_context stream_name stream_id stream_revision]
        )
        rationale = object_schema(
          properties: {
            code: identifier,
            summary: { type: "string", minLength: 1, maxLength: 500 }
          },
          required: %w[code summary]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            decision_id: identifier,
            interpretation_id: identifier,
            expected_head:,
            rationale:
          ),
          required: %w[
            command_id actor decision_id interpretation_id expected_head rationale
          ]
        )
      end

      def agent_choice_record
        option = object_schema(
          properties: {
            option_id: identifier,
            summary: { type: "string", minLength: 1, maxLength: 500 }
          },
          required: %w[option_id summary]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            choice_id: identifier,
            choice_type: { type: "string", const: "testing.framework" },
            selected: option,
            alternatives: {
              type: "array",
              maxItems: 10,
              uniqueItems: true,
              items: option
            },
            reason_summary: { type: "string", minLength: 1, maxLength: 1_000 },
            context: decision_query_context,
            decision_context: decision_context_v1
          ),
          required: %w[
            command_id actor choice_id choice_type selected alternatives reason_summary
            context decision_context
          ]
        )
      end

      def candidate_submit
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            candidate_id: identifier,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            repository_id: uuid_v7,
            target_branch: { type: "string", minLength: 1, maxLength: 255 },
            base_commit_oid: git_oid,
            head_commit_oid: git_oid,
            checkpoint_kind: { type: "string", enum: Types::CANDIDATE_CHECKPOINT_KINDS },
            lease_set_id: uuid_v7,
            leases: {
              type: "array",
              minItems: 1,
              maxItems: 32,
              uniqueItems: true,
              items: lease_renewal_reference
            },
            change_manifest: candidate_change_manifest,
            build_context: { anyOf: [ candidate_build_context, { type: "null" } ] }
          ),
          required: %w[
            command_id actor candidate_id change_set_id work_item_id attempt_id repository_id
            target_branch base_commit_oid head_commit_oid checkpoint_kind lease_set_id leases
            change_manifest
          ]
        )
      end

      def skill_publish
        asset = object_schema(
          properties: {
            path: {
              type: "string",
              minLength: 1,
              maxLength: Types::SKILL_ASSET_PATH_MAXIMUM_BYTES,
              description: "Caller-chosen relative POSIX path inside this complete Skill revision."
            },
            media_type: {
              type: "string",
              minLength: 1,
              maxLength: 255,
              pattern: "^[\\x21-\\x7e]+$",
              description: "Media type observed by the caller; the server does not infer content type."
            },
            executable: {
              type: "boolean",
              description: "Whether a retrieving client should treat the passive asset as executable after authorization."
            },
            content_base64: {
              type: "string",
              maxLength: Types::SKILL_ASSET_BASE64_MAXIMUM_BYTES,
              pattern: "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$",
              description: "Canonical unwrapped Base64 for the exact asset bytes."
            }
          },
          required: %w[path media_type executable content_base64]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            name: {
              type: "string",
              minLength: 1,
              maxLength: Types::SKILL_NAME_MAXIMUM_BYTES,
              description: "Exact caller-chosen Skill name; the same name in another scope is a different Skill."
            },
            scope: {
              type: "string",
              minLength: 1,
              maxLength: Types::SKILL_SCOPE_MAXIMUM_BYTES,
              description: "Exact caller/user-chosen applicability scope; the server infers no scope hierarchy."
            },
            expected_revision: {
              type: "integer",
              minimum: 0,
              description: "Zero creates the name/scope tuple; otherwise use the revision returned by skill_get."
            },
            description: {
              type: "string",
              maxLength: Types::SKILL_DESCRIPTION_MAXIMUM_BYTES,
              description: "Discovery summary explaining what the instructions do and when an agent should use them."
            },
            instructions: {
              type: "string",
              minLength: 1,
              maxLength: Types::SKILL_INSTRUCTIONS_MAXIMUM_BYTES,
              description: "Complete reusable instructions selected and normalized by the caller."
            },
            assets: {
              type: "array",
              maxItems: Types::SKILL_ASSET_MAXIMUM_COUNT,
              items: asset,
              description: "Complete passive asset snapshot for this revision, not a partial patch."
            }
          ),
          required: %w[
            command_id actor name scope expected_revision description instructions assets
          ]
        )
      end

      def skill_publish_batch
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            batch_id: uuid_v7.merge(
              description: "Stable caller-generated UUIDv7 used to resume or inspect this asynchronous Batch Saga."
            ),
            items: {
              type: "array",
              minItems: 1,
              maxItems: Types::OPERATION_BATCH_MAXIMUM_ITEMS,
              items: skill_publish,
              description: "Complete ordinary skill_publish requests selected by the caller; outcomes are independent."
            }
          ),
          required: %w[command_id actor batch_id items]
        )
      end

      def operation_batch_cancel
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            batch_id: uuid_v7
          ),
          required: %w[command_id actor batch_id]
        )
      end

      def operation_batch_get
        object_schema(
          properties: {
            batch_id: uuid_v7,
            after_index: {
              anyOf: [
                { type: "integer", minimum: 0, maximum: Types::OPERATION_BATCH_MAXIMUM_ITEMS - 1 },
                { type: "null" }
              ]
            },
            limit: {
              anyOf: [
                {
                  type: "integer",
                  minimum: 1,
                  maximum: Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS
                },
                { type: "null" }
              ]
            }
          },
          required: %w[batch_id]
        )
      end

      def skill_get
        object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: Types::SKILL_NAME_MAXIMUM_BYTES },
            scope: { type: "string", minLength: 1, maxLength: Types::SKILL_SCOPE_MAXIMUM_BYTES },
            revision: {
              anyOf: [ { type: "integer", minimum: 1 }, { type: "null" } ],
              description: "Omit for the latest available projected revision; provide a revision to pin one immutable snapshot."
            }
          },
          required: %w[name scope]
        )
      end

      def skill_list
        object_schema(
          properties: {
            name: {
              anyOf: [
                { type: "string", minLength: 1, maxLength: Types::SKILL_NAME_MAXIMUM_BYTES },
                { type: "null" }
              ]
            },
            scope: {
              anyOf: [
                { type: "string", minLength: 1, maxLength: Types::SKILL_SCOPE_MAXIMUM_BYTES },
                { type: "null" }
              ]
            },
            after_skill_id: {
              anyOf: [
                { type: "string", pattern: "^skill:v1:[0-9a-f]{64}$" },
                { type: "null" }
              ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: []
        )
      end

      def skill_asset_get
        object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: Types::SKILL_NAME_MAXIMUM_BYTES },
            scope: { type: "string", minLength: 1, maxLength: Types::SKILL_SCOPE_MAXIMUM_BYTES },
            path: { type: "string", minLength: 1, maxLength: Types::SKILL_ASSET_PATH_MAXIMUM_BYTES },
            revision: {
              anyOf: [ { type: "integer", minimum: 1 }, { type: "null" } ],
              description: "Pass the revision returned by skill_get to fetch content from the same immutable snapshot."
            }
          },
          required: %w[name scope path]
        )
      end

      def development_artifact_capture
        content = object_schema(
          properties: {
            encoding: {
              type: "string",
              enum: %w[utf-8 binary],
              description: "Use utf-8 with text for valid UTF-8 bytes; otherwise use binary with base64."
            },
            media_type: {
              type: "string",
              minLength: 1,
              maxLength: 255,
              pattern: "^[\\x21-\\x7e]+$",
              description: "Media type observed by the caller; the server does not inspect or infer it."
            },
            text: {
              type: "string",
              maxLength: Types::DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES,
              description: "Exact UTF-8 content bytes represented as text; do not send a filesystem path in place of content."
            },
            base64: {
              type: "string",
              maxLength: Types::DEVELOPMENT_ARTIFACT_CONTENT_BASE64_MAXIMUM_BYTES,
              pattern: "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$",
              description: "Canonical unwrapped Base64 for exact non-UTF-8 or binary bytes."
            }
          },
          required: %w[encoding media_type],
          one_of: [
            { properties: { encoding: { const: "utf-8" } }, required: %w[encoding text] },
            { properties: { encoding: { const: "binary" } }, required: %w[encoding base64] }
          ]
        )
        source = object_schema(
          properties: {
            kind: {
              type: "string",
              enum: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS,
              description: "How the caller obtained the bytes or reference; this is provenance, not Artifact classification."
            },
            locator: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES,
              description: "Stable caller-owned logical locator used as provenance and identity only; the server never dereferences it."
            },
            revision: {
              type: [ "string", "null" ],
              maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES,
              description: "Optional caller-observed immutable source revision, such as a commit OID or document version."
            },
            observed_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$",
              description: "Canonical UTC time at which the caller observed these exact source bytes."
            },
            collector: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_COLLECTOR_MAXIMUM_BYTES,
              description: "Caller-chosen identifier for the agent, tool, or procedure that observed the source."
            }
          },
          required: %w[kind locator revision observed_at collector]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            scope: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES,
              description: "Exact caller/user-chosen project or context scope used to retrieve this Artifact."
            },
            title: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES,
              description: "Concise human-readable title for the selected development-memory item."
            },
            kind: {
              type: "string",
              enum: Types::DEVELOPMENT_ARTIFACT_KINDS,
              description: "Semantic role of the content in development; choose from meaning, not filename or directory alone."
            },
            labels: {
              type: "array",
              maxItems: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT,
              uniqueItems: true,
              description: "Caller-chosen exact facets used for retrieval; labels do not replace the broad kind.",
              items: {
                type: "string",
                minLength: 1,
                maxLength: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
              }
            },
            content:,
            source:
          ),
          required: %w[command_id actor scope title kind labels content source]
        )
      end

      def development_artifact_capture_batch
        operation_batch_schema(development_artifact_capture)
      end

      def development_artifact_classification_correct
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            observation_id: {
              type: "string",
              pattern: "^artifact-observation:v1:[0-9a-f]{64}$",
              description: "Exact immutable source observation whose semantic classification is being corrected."
            },
            expected_revision: {
              type: "integer",
              minimum: 1,
              maximum: Types::DEVELOPMENT_ARTIFACT_CLASSIFICATION_MAXIMUM_REVISIONS,
              description: "Current classification revision returned by development_artifact_get; stale revisions are rejected."
            },
            title: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES
            },
            kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_KINDS },
            labels: {
              type: "array",
              maxItems: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT,
              uniqueItems: true,
              items: {
                type: "string",
                minLength: 1,
                maxLength: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
              }
            },
            reason: {
              type: "string",
              minLength: 1,
              maxLength: 1_000,
              description: "Why the caller is correcting semantic classification; bytes and provenance are unchanged."
            }
          ),
          required: %w[
            command_id actor observation_id expected_revision title kind labels reason
          ]
        )
      end

      def development_artifact_relation_declare
        target = object_schema(
          properties: {
            kind: {
              type: "string",
              enum: Types::DEVELOPMENT_ARTIFACT_CANONICAL_TARGET_KINDS,
              description: "Canonical target ontology. Internal identities must already exist in pg_eventstore; external accepts only an absolute HTTP(S) URL and remains unverified."
            },
            id: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES,
              description: "Exact authoritative internal identity, or an absolute HTTP(S) URL for external. The server validates internal existence transactionally and never dereferences external URLs."
            }
          },
          required: %w[kind id]
        )
        attributes = object_schema(
          properties: {
            path: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_RELATION_PATH_MAXIMUM_BYTES,
              description: "Literal relative POSIX link path observed by the caller. Allowed for references; documents may use it only as a document-slot label. Parent and current-directory segments are preserved."
            },
            fragment: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_RELATION_FRAGMENT_MAXIMUM_BYTES,
              description: "Optional literal link fragment without #, allowed only for references with path."
            },
            normalized_locator: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES,
              description: "Optional source-relative locator normalized client-side for exact lookup, allowed only for references with path; the server neither computes nor dereferences it."
            }
          },
          required: []
        )
        supersedes = object_schema(
          properties: {
            relation_id: {
              type: "string",
              pattern: "^artifact-relation:v1:[0-9a-f]{64}$",
              description: "Exact active relation being immutably corrected by this replacement."
            },
            reason: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_RELATION_SUPERSESSION_REASON_MAXIMUM_BYTES
            }
          },
          required: %w[relation_id reason]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            source_artifact_id: {
              type: "string",
              pattern: "^artifact:v1:[0-9a-f]{64}$",
              description: "Captured Artifact from which the directed relationship originates."
            },
            relation: {
              type: "string",
              enum: Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS,
              description: "Server-owned directed edge. Parent/index is the source for references and contains; documents and evidences point from the Artifact to the described/evidenced target; produced_by_import targets an Operation Batch."
            },
            target:,
            attributes:,
            supersedes: supersedes.merge(
              description: "Optional immutable correction; omit for an ordinary declaration."
            )
          ),
          required: %w[command_id actor source_artifact_id relation target attributes]
        )
      end

      def development_artifact_relation_declare_batch
        operation_batch_schema(development_artifact_relation_declare)
      end

      def development_artifact_get
        object_schema(
          properties: {
            artifact_id: { type: "string", pattern: "^artifact:v1:[0-9a-f]{64}$" },
            observation_id: {
              anyOf: [
                { type: "string", pattern: "^artifact-observation:v1:[0-9a-f]{64}$" },
                { type: "null" }
              ],
              description: "Optional exact immutable observation; omit to receive the latest available observation."
            }
          },
          required: %w[artifact_id]
        )
      end

      def development_artifact_content_get
        object_schema(
          properties: {
            artifact_id: { type: "string", pattern: "^artifact:v1:[0-9a-f]{64}$" }
          },
          required: %w[artifact_id]
        )
      end

      def development_artifact_relation_list
        cursor = object_schema(
          properties: {
            after_observed_sequence: { type: "integer", minimum: 0 },
            through_observed_sequence: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            after_declared_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            after_relation_id: {
              anyOf: [
                { type: "string", pattern: "^artifact-relation:v1:[0-9a-f]{64}$" },
                { type: "null" }
              ]
            }
          },
          required: %w[
            after_observed_sequence
            through_observed_sequence
            after_declared_global_position
            after_relation_id
          ]
        )
        object_schema(
          properties: {
            artifact_id: { type: "string", pattern: "^artifact:v1:[0-9a-f]{64}$" },
            direction: {
              anyOf: [ { type: "string", enum: %w[incoming outgoing both] }, { type: "null" } ]
            },
            relation: {
              anyOf: [
                { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS },
                { type: "null" }
              ]
            },
            include_superseded: { anyOf: [ { type: "boolean" }, { type: "null" } ] },
            cursor: { anyOf: [ cursor, { type: "null" } ] },
            limit: {
              anyOf: [
                {
                  type: "integer",
                  minimum: 1,
                  maximum: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
                },
                { type: "null" }
              ]
            }
          },
          required: %w[artifact_id]
        )
      end

      def development_artifact_locator_resolve
        cursor = object_schema(
          properties: {
            after_observed_sequence: {
              type: "integer",
              minimum: 0,
              description: "Projection-observation lower bound returned by the previous page."
            },
            through_observed_sequence: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ],
              description: "Fixed projection-observation upper bound, or null to open a new window."
            },
            after_current_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ],
              description: "Current-classification event position inside a fixed observation window."
            },
            after_observation_id: {
              anyOf: [
                { type: "string", pattern: "^artifact-observation:v1:[0-9a-f]{64}$" },
                { type: "null" }
              ],
              description: "Immutable observation tie-breaker inside a fixed observation window."
            }
          },
          required: %w[
            after_observed_sequence
            through_observed_sequence
            after_current_global_position
            after_observation_id
          ]
        )
        object_schema(
          properties: {
            scope: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES,
              description: "Exact caller-owned Artifact scope."
            },
            source_kind: {
              type: "string",
              enum: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS,
              description: "Exact source-kind discriminator."
            },
            locator: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES,
              description: "Exact caller-normalized logical locator; the server does not resolve paths, fetch URLs, or select a latest version."
            },
            source_revision: {
              anyOf: [
                {
                  type: "string",
                  maxLength: Types::DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES
                },
                { type: "null" }
              ],
              description: "Optional exact revision. Omit to match every revision; null matches only artifacts captured without a revision."
            },
            cursor: { anyOf: [ cursor, { type: "null" } ] },
            limit: {
              anyOf: [
                {
                  type: "integer",
                  minimum: 1,
                  maximum: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
                },
                { type: "null" }
              ]
            }
          },
          required: %w[scope source_kind locator]
        )
      end

      def development_artifact_list
        relation_target = object_schema(
          properties: {
            kind: { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_TARGET_KINDS },
            id: {
              type: "string",
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES
            }
          },
          required: %w[kind id]
        )
        object_schema(
          properties: {
            scope: {
              type: [ "string", "null" ],
              minLength: 1,
              maxLength: Types::DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES
            },
            kind: { anyOf: [ { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_KINDS }, { type: "null" } ] },
            labels: {
              type: "array",
              maxItems: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT,
              uniqueItems: true,
              items: {
                type: "string",
                minLength: 1,
                maxLength: Types::DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
              }
            },
            source_kind: {
              anyOf: [
                { type: "string", enum: Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS },
                { type: "null" }
              ]
            },
            relation_target: { anyOf: [ relation_target, { type: "null" } ] },
            after_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            limit: {
              anyOf: [
                {
                  type: "integer",
                  minimum: 1,
                  maximum: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS
                },
                { type: "null" }
              ]
            }
          },
          required: []
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

      def agent_choice_get
        object_schema(
          properties: { choice_id: identifier },
          required: %w[choice_id]
        )
      end

      def candidate_get
        object_schema(
          properties: { candidate_id: identifier },
          required: %w[candidate_id]
        )
      end

      def candidate_list
        object_schema(
          properties: {
            attempt_id: identifier,
            after_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: %w[attempt_id]
        )
      end

      def candidate_impact_get
        object_schema(
          properties: {
            candidate_id: identifier,
            direction: { type: "string", enum: %w[incoming outgoing] },
            after_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: %w[candidate_id direction]
        )
      end

      def verification_obligations_list
        filter_keys = %w[
          obligation_id change_set_id candidate_id work_item_id repository_id kind enforcement status
          claimant_id claim_state
        ]
        object_schema(
          properties: {
            obligation_id: nullable_identifier,
            change_set_id: nullable_identifier,
            candidate_id: nullable_identifier,
            work_item_id: nullable_identifier,
            repository_id: { anyOf: [ uuid_v7, { type: "null" } ] },
            kind: nullable_enum([ "candidate_compatibility" ]),
            enforcement: nullable_enum(%w[verification_gate merge_gate]),
            status: nullable_enum(Types::VERIFICATION_OBLIGATION_STATUSES),
            claimant_id: nullable_identifier,
            claim_state: nullable_enum(Types::VERIFICATION_OBLIGATION_CLAIM_STATES),
            after_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: []
        ).merge(anyOf: filter_keys.map { { required: [ _1 ] } })
      end

      def verification_obligation_claim
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            obligation_id: identifier,
            claim_duration_seconds: { type: "integer", minimum: 30, maximum: 3_600 }
          ),
          required: %w[command_id actor obligation_id claim_duration_seconds]
        )
      end

      def compatibility_assessment_submit
        finding = object_schema(
          properties: {
            code: { type: "string", minLength: 1, maxLength: 100 },
            severity: { type: "string", enum: Types::VERIFICATION_EVIDENCE_FINDING_SEVERITIES },
            summary: { type: "string", minLength: 1, maxLength: 2_000 },
            path: { type: [ "string", "null" ], minLength: 1, maxLength: 1_024 }
          },
          required: %w[code severity summary]
        )
        candidate = object_schema(
          properties: { candidate_id: identifier, head_commit_oid: git_oid },
          required: %w[candidate_id head_commit_oid]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            obligation_id: identifier,
            claim: object_schema(
              properties: {
                claim_id: uuid_v7,
                fencing_token: { type: "integer", minimum: 1 }
              },
              required: %w[claim_id fencing_token]
            ),
            binding: object_schema(
              properties: {
                obligation_validity_input_digest: {
                  type: "string",
                  pattern: "^sha256:[0-9a-f]{64}$"
                },
                source_candidate: candidate,
                target_candidate: candidate
              },
              required: %w[
                obligation_validity_input_digest source_candidate target_candidate
              ]
            ),
            assessment: object_schema(
              properties: {
                evidence_kind: {
                  type: "string",
                  enum: Types::CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS
                },
                producer: object_schema(
                  properties: {
                    name: { type: "string", minLength: 1, maxLength: 100 },
                    version: { type: "string", minLength: 1, maxLength: 100 }
                  },
                  required: %w[name version]
                ),
                run_id: identifier,
                test_suite_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
                environment_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
                dependency_graph_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
                result_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
                conclusion: { type: "string", enum: Types::VERIFICATION_EVIDENCE_CONCLUSIONS },
                findings: { type: "array", items: finding, maxItems: 32 },
                produced_at: {
                  type: "string",
                  pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
                }
              },
              required: %w[
                evidence_kind producer run_id test_suite_digest environment_digest
                dependency_graph_digest result_digest conclusion findings produced_at
              ]
            )
          ),
          required: %w[command_id actor obligation_id claim binding assessment]
        )
      end

      def verification_obligation_waive
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: [ "user" ]),
            obligation_id: identifier,
            obligation_validity_input_digest: {
              type: "string",
              pattern: "^sha256:[0-9a-f]{64}$"
            },
            reason: object_schema(
              properties: {
                code: {
                  type: "string",
                  enum: Types::VERIFICATION_OBLIGATION_WAIVER_REASON_CODES
                },
                summary: { type: "string", minLength: 1, maxLength: 2_000 }
              },
              required: %w[code summary]
            )
          ),
          required: %w[
            command_id actor obligation_id obligation_validity_input_digest reason
          ]
        )
      end

      def merge_snapshot_register
        candidate = object_schema(
          properties: { candidate_id: identifier, head_commit_oid: git_oid },
          required: %w[candidate_id head_commit_oid]
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            merge_snapshot_id: identifier,
            repository_id: uuid_v7,
            target_branch: { type: "string", minLength: 1, maxLength: 255 },
            target_base_commit_oid: git_oid,
            ordered_candidates: {
              type: "array", items: candidate, minItems: 1, maxItems: 32, uniqueItems: true
            },
            merge_commit_oid: git_oid,
            producer:,
            run_id: identifier,
            produced_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          ),
          required: %w[
            command_id actor merge_snapshot_id repository_id target_branch
            target_base_commit_oid ordered_candidates merge_commit_oid producer run_id produced_at
          ]
        )
      end

      def merge_snapshot_get
        object_schema(
          properties: { merge_snapshot_id: identifier },
          required: %w[merge_snapshot_id]
        )
      end

      def release_set_get
        object_schema(
          properties: { release_set_id: identifier },
          required: %w[release_set_id]
        )
      end

      def release_set_prepare
        registration_event = merge_authorization_event_reference(
          type: "MergeSnapshotRegistered",
          context: "DevelopmentIntegration",
          stream_name: "MergeSnapshot",
          minimum_revision: 0,
          maximum_revision: 0
        )
        verification_event = merge_authorization_event_reference(
          type: "MergeSnapshotVerified",
          context: "DevelopmentIntegration",
          stream_name: "MergeSnapshot",
          minimum_revision: 2
        )
        authorization_event = merge_authorization_event_reference(
          type: "MergeAuthorizationGranted",
          context: "DevelopmentIntegration",
          stream_name: "MergeAuthorization",
          minimum_revision: 0,
          maximum_revision: 0
        )
        member = object_schema(
          properties: {
            repository_id: uuid_v7,
            target_branch: { type: "string", minLength: 1, maxLength: 255 },
            object_format: { type: "string", enum: Types::GIT_OBJECT_FORMATS },
            merge_snapshot_id: identifier,
            snapshot_binding: object_schema(
              properties: {
                registration_event:,
                snapshot_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
                verification_event:,
                verification_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" }
              },
              required: %w[
                registration_event snapshot_digest verification_event verification_digest
              ]
            ),
            authorization_event:,
            authorization_decision_digest: {
              type: "string", pattern: "^sha256:[0-9a-f]{64}$"
            }
          },
          required: %w[
            repository_id target_branch object_format merge_snapshot_id snapshot_binding
            authorization_event authorization_decision_digest
          ]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            release_set_id: identifier,
            ordered_members: {
              type: "array",
              items: member,
              minItems: Types::RELEASE_SET_MINIMUM_MEMBERS,
              maxItems: Types::RELEASE_SET_MAXIMUM_MEMBERS
            }
          ),
          required: %w[command_id actor release_set_id ordered_members]
        )
      end

      def release_repository_integration_record
        observation_event = merge_authorization_event_reference(
          type: "MergeObserved",
          context: "DevelopmentIntegration",
          stream_name: "MergeSnapshot",
          minimum_revision: 3
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        failure = object_schema(
          properties: {
            code: identifier,
            summary: { type: "string", minLength: 1, maxLength: 2_000 },
            producer:,
            run_id: identifier,
            result_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            occurred_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          },
          required: %w[code summary producer run_id result_digest occurred_at]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            release_set_id: identifier,
            repository_id: uuid_v7,
            attempt_id: identifier,
            outcome: { type: "string", enum: Types::RELEASE_SET_INTEGRATION_OUTCOMES },
            merge_observation_event: { anyOf: [ observation_event, { type: "null" } ] },
            observation_digest: nullable_sha256_digest,
            failure: { anyOf: [ failure, { type: "null" } ] }
          ),
          required: %w[
            command_id actor release_set_id repository_id attempt_id outcome
            merge_observation_event observation_digest failure
          ]
        )
      end

      def release_verification_record
        integration_event = merge_authorization_event_reference(
          type: "RepositoryIntegrationRecorded",
          context: "DevelopmentIntegration",
          stream_name: "ReleaseSet",
          minimum_revision: 1
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        finding = object_schema(
          properties: {
            code: identifier,
            severity: { type: "string", enum: %w[info warning error critical] },
            summary: { type: "string", minLength: 1, maxLength: 2_000 },
            repository_id: {
              anyOf: [
                uuid_v7,
                { type: "null" }
              ]
            }
          },
          required: %w[code severity summary repository_id]
        )
        evidence = object_schema(
          properties: {
            producer:,
            run_id: identifier,
            environment_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            result_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            outcome: { type: "string", enum: Types::RELEASE_SET_VERIFICATION_OUTCOMES },
            findings: { type: "array", maxItems: 32, items: finding },
            produced_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          },
          required: %w[
            producer run_id environment_digest result_digest outcome findings produced_at
          ]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            release_set_id: identifier,
            integration_events: {
              type: "array",
              minItems: Types::RELEASE_SET_MINIMUM_MEMBERS,
              maxItems: Types::RELEASE_SET_MAXIMUM_MEMBERS,
              uniqueItems: true,
              items: integration_event
            },
            evidence:
          ),
          required: %w[command_id actor release_set_id integration_events evidence]
        )
      end

      def release_activation_record
        verification_event = merge_authorization_event_reference(
          type: "ReleaseSetVerificationRecorded",
          context: "DevelopmentIntegration",
          stream_name: "ReleaseSet",
          minimum_revision: 1
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        activation_point = object_schema(
          properties: {
            kind: { type: "string", enum: Types::RELEASE_SET_ACTIVATION_POINT_KINDS },
            environment: identifier,
            external_reference: { type: "string", minLength: 1, maxLength: 1_000 },
            state_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            producer:,
            run_id: identifier,
            activated_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          },
          required: %w[
            kind environment external_reference state_digest producer run_id activated_at
          ]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            release_set_id: identifier,
            verification_event:,
            verification_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            activation_point:
          ),
          required: %w[
            command_id actor release_set_id verification_event verification_digest activation_point
          ]
        )
      end

      def release_compensation_complete
        request_event = merge_authorization_event_reference(
          type: "ReleaseSetCompensationRequested",
          context: "DevelopmentIntegration",
          stream_name: "ReleaseSet",
          minimum_revision: 2
        )
        integration_event = merge_authorization_event_reference(
          type: "RepositoryIntegrationRecorded",
          context: "DevelopmentIntegration",
          stream_name: "ReleaseSet",
          minimum_revision: 1
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        evidence = object_schema(
          properties: {
            repository_id: uuid_v7,
            integration_event:,
            action: { type: "string", enum: Types::RELEASE_SET_COMPENSATION_ACTIONS },
            external_reference: { type: "string", minLength: 1, maxLength: 1_000 },
            result_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            producer:,
            run_id: identifier,
            compensated_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          },
          required: %w[
            repository_id integration_event action external_reference result_digest producer
            run_id compensated_at
          ]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            release_set_id: identifier,
            compensation_request_event: request_event,
            evidence: {
              type: "array",
              minItems: 1,
              maxItems: Types::RELEASE_SET_MAXIMUM_MEMBERS,
              uniqueItems: true,
              items: evidence
            }
          ),
          required: %w[
            command_id actor release_set_id compensation_request_event evidence
          ]
        )
      end

      def merge_verification_submit
        candidate = object_schema(
          properties: { candidate_id: identifier, head_commit_oid: git_oid },
          required: %w[candidate_id head_commit_oid]
        )
        snapshot_event = object_schema(
          properties: {
            event_id: uuid_v7,
            type: { type: "string", const: "MergeSnapshotRegistered" },
            stream_context: { type: "string", const: "DevelopmentIntegration" },
            stream_name: { type: "string", const: "MergeSnapshot" },
            stream_id: identifier,
            stream_revision: { type: "integer", const: 0 }
          },
          required: %w[event_id type stream_context stream_name stream_id stream_revision]
        )
        binding = object_schema(
          properties: {
            snapshot_event:,
            snapshot_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            repository_id: uuid_v7,
            target_branch: { type: "string", minLength: 1, maxLength: 255 },
            object_format: { type: "string", enum: Types::GIT_OBJECT_FORMATS },
            target_base_commit_oid: git_oid,
            ordered_candidates: {
              type: "array", items: candidate, minItems: 1, maxItems: 32, uniqueItems: true
            },
            merge_commit_oid: git_oid
          },
          required: %w[
            snapshot_event snapshot_digest repository_id target_branch object_format
            target_base_commit_oid ordered_candidates merge_commit_oid
          ]
        )
        finding = object_schema(
          properties: {
            code: { type: "string", minLength: 1, maxLength: 100 },
            severity: { type: "string", enum: Types::VERIFICATION_EVIDENCE_FINDING_SEVERITIES },
            summary: { type: "string", minLength: 1, maxLength: 2_000 },
            path: { anyOf: [ { type: "string", minLength: 1, maxLength: 1_024 }, { type: "null" } ] }
          },
          required: %w[code severity summary]
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        assessment = object_schema(
          properties: {
            evidence_kind: {
              type: "string", enum: Types::MERGE_SNAPSHOT_VERIFICATION_EVIDENCE_KINDS
            },
            producer:,
            run_id: identifier,
            test_suite_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            environment_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            result_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            conclusion: { type: "string", enum: Types::VERIFICATION_EVIDENCE_CONCLUSIONS },
            findings: { type: "array", items: finding, maxItems: 32 },
            produced_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          },
          required: %w[
            evidence_kind producer run_id test_suite_digest environment_digest result_digest
            conclusion findings produced_at
          ]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            merge_snapshot_id: identifier,
            binding:,
            assessment:
          ),
          required: %w[command_id actor merge_snapshot_id binding assessment]
        )
      end

      def merge_authorization_request
        registration_event = merge_authorization_event_reference(
          type: "MergeSnapshotRegistered",
          context: "DevelopmentIntegration",
          stream_name: "MergeSnapshot",
          minimum_revision: 0,
          maximum_revision: 0
        )
        verification_event = merge_authorization_event_reference(
          type: "MergeSnapshotVerified",
          context: "DevelopmentIntegration",
          stream_name: "MergeSnapshot",
          minimum_revision: 2
        )
        decision_event = {
          anyOf: %w[DecisionActivated DecisionDefinitionCorrected].map do |type|
            merge_authorization_event_reference(
              type:,
              context: "HumanGuidance",
              stream_name: "Decision",
              minimum_revision: 1
            )
          end
        }
        partition_event = merge_authorization_event_reference(
          type: "DecisionPartitionAdvanced",
          context: "HumanGuidance",
          stream_name: "DecisionPartition",
          minimum_revision: 0
        )
        expected_policy = object_schema(
          properties: {
            partition_event:,
            head: object_schema(
              properties: {
                decision_id: identifier,
                decision_revision: { type: "integer", minimum: 1 },
                event: decision_event
              },
              required: %w[decision_id decision_revision event]
            ),
            definition_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" }
          },
          required: %w[partition_event head definition_digest]
        )
        producer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            merge_snapshot_id: identifier,
            snapshot_binding: object_schema(
              properties: {
                registration_event:,
                snapshot_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
                verification_event:,
                verification_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" }
              },
              required: %w[
                registration_event snapshot_digest verification_event verification_digest
              ]
            ),
            target_base_observation: object_schema(
              properties: {
                repository_id: uuid_v7,
                target_branch: { type: "string", minLength: 1, maxLength: 255 },
                object_format: { type: "string", enum: Types::GIT_OBJECT_FORMATS },
                commit_oid: git_oid,
                observer: producer,
                run_id: identifier,
                observed_at: {
                  type: "string",
                  pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
                }
              },
              required: %w[
                repository_id target_branch object_format commit_oid observer run_id observed_at
              ]
            ),
            expected_impact_policy: { anyOf: [ expected_policy, { type: "null" } ] }
          ),
          required: %w[
            command_id actor merge_snapshot_id snapshot_binding target_base_observation
            expected_impact_policy
          ]
        )
      end

      def merge_observation_record
        authorization_event = merge_authorization_event_reference(
          type: "MergeAuthorizationGranted",
          context: "DevelopmentIntegration",
          stream_name: "MergeAuthorization",
          minimum_revision: 0,
          maximum_revision: 0
        )
        observer = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            version: { type: "string", minLength: 1, maxLength: 100 }
          },
          required: %w[name version]
        )
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            merge_snapshot_id: identifier,
            authorization_event:,
            authorization_decision_digest: {
              type: "string", pattern: "^sha256:[0-9a-f]{64}$"
            },
            repository_id: uuid_v7,
            target_branch: { type: "string", minLength: 1, maxLength: 255 },
            object_format: { type: "string", enum: Types::GIT_OBJECT_FORMATS },
            target_before_commit_oid: git_oid,
            target_after_commit_oid: git_oid,
            observer:,
            run_id: identifier,
            observed_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          ),
          required: %w[
            command_id actor merge_snapshot_id authorization_event
            authorization_decision_digest repository_id target_branch object_format
            target_before_commit_oid target_after_commit_oid observer run_id observed_at
          ]
        )
      end

      def candidate_impact_surface_submit
        object_schema(
          properties: common_mutation_properties.merge(
            actor: agent_actor,
            candidate_id: identifier,
            repository_id: uuid_v7,
            head_commit_oid: git_oid,
            manifest_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            build_context_digest: nullable_sha256_digest,
            analyzer_version: { type: "string", minLength: 1, maxLength: 100 },
            surface: candidate_impact_surface
          ),
          required: %w[
            command_id actor candidate_id repository_id head_commit_oid manifest_digest
            analyzer_version surface
          ]
        )
      end

      def merge_authorization_event_reference(type:, context:, stream_name:, minimum_revision:, maximum_revision: nil)
        revision = { type: "integer", minimum: minimum_revision }
        revision[:maximum] = maximum_revision if maximum_revision
        object_schema(
          properties: {
            event_id: uuid_v7,
            type: { type: "string", const: type },
            stream_context: { type: "string", const: context },
            stream_name: { type: "string", const: stream_name },
            stream_id: identifier,
            stream_revision: revision
          },
          required: %w[event_id type stream_context stream_name stream_id stream_revision]
        )
      end

      def agent_choice_impact_list
        object_schema(
          properties: {
            attempt_id: identifier,
            after_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: %w[attempt_id]
        )
      end

      def attempt_list
        object_schema(
          properties: {
            work_item_id: identifier,
            after_authorized_global_position: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: %w[work_item_id]
        )
      end

      def guidance_get
        object_schema(
          properties: { message_id: identifier },
          required: %w[message_id]
        )
      end

      def decision_interpretation_list
        object_schema(
          properties: {
            message_id: identifier,
            after_revision: {
              anyOf: [ { type: "integer", minimum: -1 }, { type: "null" } ]
            },
            limit: {
              anyOf: [ { type: "integer", minimum: 1, maximum: 100 }, { type: "null" } ]
            }
          },
          required: %w[message_id]
        )
      end

      def decision_get
        object_schema(
          properties: { decision_id: identifier },
          required: %w[decision_id]
        )
      end

      def decision_list
        object_schema(
          properties: {
            repository_id: uuid_v7,
            topic_id: nullable_identifier,
            policy_status: {
              anyOf: [
                { type: "string", enum: Types::DECISION_POLICY_STATUSES },
                { type: "null" }
              ]
            },
            after_decision_id: nullable_identifier,
            limit: {
              anyOf: [
                {
                  type: "integer",
                  minimum: 1,
                  maximum: Types::DECISION_DISCOVERY_MAXIMUM_ITEMS
                },
                { type: "null" }
              ]
            }
          },
          required: %w[repository_id]
        )
      end

      def decision_resolve
        object_schema(
          properties: {
            topic_id: identifier,
            context: decision_query_context
          },
          required: %w[topic_id context]
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
          command_id: public_command_id,
          actor: attributed_actor(enum: Types::ACTOR_KINDS)
        }
      end

      def operation_batch_schema(item_schema)
        object_schema(
          properties: common_mutation_properties.merge(
            actor: attributed_actor(enum: %w[agent user]),
            batch_id: uuid_v7.merge(
              description: "Stable caller-generated UUIDv7 used to resume or inspect this asynchronous Batch Saga."
            ),
            items: {
              type: "array",
              minItems: 1,
              maxItems: Types::OPERATION_BATCH_MAXIMUM_ITEMS,
              items: item_schema,
              description: "Complete ordinary target-tool requests selected by the caller; each has an independent outcome."
            }
          ),
          required: %w[command_id actor batch_id items]
        )
      end

      def agent_actor
        attributed_actor(const: "agent")
      end

      def attributed_actor(enum: nil, const: nil)
        kind = const ? { type: "string", const: } : { type: "string", enum: }
        object_schema(
          properties: {
            kind:,
            id: identifier
          },
          required: %w[kind id]
        ).merge(description: ACTOR_ATTRIBUTION_DESCRIPTION)
      end

      def decision_query_context(require_nullable_fields: false)
        required = %w[
          repository_id change_set_id work_item_id attempt_id phase language paths agent_role
        ]
        required += %w[workspace_id environment] if require_nullable_fields
        object_schema(
          properties: {
            workspace_id: nullable_identifier,
            repository_id: uuid_v7,
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            phase: { type: "string", enum: Types::DECISION_PHASES },
            language: identifier,
            paths: {
              type: "array",
              maxItems: 32,
              uniqueItems: true,
              items: { type: "string", minLength: 1, maxLength: 1_024 }
            },
            environment: nullable_identifier,
            agent_role: identifier
          },
          required:
        )
      end

      def decision_context_v1
        object_schema(
          properties: {
            document: decision_context_document,
            digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            resolved_at: {
              type: "string",
              pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
            }
          },
          required: %w[document digest resolved_at]
        )
      end

      def decision_context_document
        object_schema(
          properties: {
            schema: { type: "string", const: "decision-context/v1" },
            resolution_policy: {
              type: "string",
              enum: %w[testing-framework-resolution/v1 single-choice-resolution/v1]
            },
            topic_id: identifier,
            query_context: decision_query_context(require_nullable_fields: true),
            partitions: {
              type: "array",
              minItems: 4,
              maxItems: 5,
              uniqueItems: true,
              items: decision_partition_observation
            },
            effective_decision: {
              anyOf: [ resolved_decision, { type: "null" } ]
            },
            shadowed_decisions: {
              type: "array",
              maxItems: 32,
              items: object_schema(
                properties: {
                  decision: resolved_decision,
                  reason: { type: "string", const: "less_specific" }
                },
                required: %w[decision reason]
              )
            },
            conflict: {
              anyOf: [ decision_context_conflict, { type: "null" } ]
            }
          },
          required: %w[
            schema resolution_policy topic_id query_context partitions effective_decision
            shadowed_decisions conflict
          ]
        )
      end

      def decision_partition_observation
        object_schema(
          properties: {
            partition: object_schema(
              properties: {
                partition_id: identifier,
                topic_root: identifier,
                anchor_kind: { type: "string", enum: Types::DECISION_PARTITION_ANCHOR_KINDS },
                anchor_id: identifier
              },
              required: %w[partition_id topic_root anchor_kind anchor_id]
            ),
            partition_revision: {
              anyOf: [ { type: "integer", minimum: 0 }, { type: "null" } ]
            },
            event: { anyOf: [ decision_event_reference, { type: "null" } ] },
            active_decisions: {
              type: "array",
              maxItems: 32,
              uniqueItems: true,
              items: decision_head
            }
          },
          required: %w[partition partition_revision event active_decisions]
        )
      end

      def decision_event_reference
        object_schema(
          properties: {
            event_id: uuid_v7,
            type: identifier,
            stream_context: identifier,
            stream_name: identifier,
            stream_id: identifier,
            stream_revision: { type: "integer", minimum: 0 }
          },
          required: %w[event_id type stream_context stream_name stream_id stream_revision]
        )
      end

      def decision_head
        object_schema(
          properties: {
            decision_id: identifier,
            decision_revision: { type: "integer", minimum: 0 },
            event: decision_event_reference
          },
          required: %w[decision_id decision_revision event]
        )
      end

      def resolved_decision
        object_schema(
          properties: {
            head: decision_head,
            definition_digest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            topic_id: identifier,
            effect: { type: "string", enum: Types::DECISION_EFFECTS },
            modality: { type: "string", enum: Types::DECISION_MODALITIES },
            value: interpretation_value,
            enforcement: object_schema(
              properties: {
                level: { type: "string", enum: Types::ENFORCEMENT_LEVELS },
                retroactivity: { type: "string", enum: Types::RETROACTIVITY_KINDS },
                on_violation: { type: "string", enum: Types::VIOLATION_ACTIONS }
              },
              required: %w[level retroactivity on_violation]
            ),
            anchor_kind: {
              type: "string",
              enum: Write::DecisionContexts::ResolvedDecisionV1::ANCHOR_KINDS
            },
            anchor_rank: { type: "integer", minimum: 1, maximum: 5 },
            applicability_reasons: identifier_array(max_items: 10).merge(minItems: 1)
          },
          required: %w[
            head definition_digest topic_id effect modality value enforcement anchor_kind
            anchor_rank applicability_reasons
          ]
        )
      end

      def decision_context_conflict
        object_schema(
          properties: {
            decisions: {
              type: "array",
              minItems: 2,
              maxItems: 32,
              uniqueItems: true,
              items: resolved_decision
            },
            reason: { type: "string", const: "tied_most_specific" }
          },
          required: %w[decisions reason]
        )
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

      def public_command_id
        {
          type: "string",
          pattern: "^(?!internal:)[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$"
        }
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

      def canonical_timestamp
        {
          type: "string",
          pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{6}Z$"
        }
      end

      def write_set_resource
        object_schema(
          properties: {
            kind: { type: "string", enum: %w[file directory] },
            path: {
              type: "string",
              minLength: 1,
              maxLength: 1_024,
              pattern: "^(?!.*\\\\).+$"
            },
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

      def candidate_change_manifest
        object_schema(
          properties: {
            collector_version: { type: "string", minLength: 1, maxLength: 100 },
            files: {
              type: "array",
              minItems: 1,
              maxItems: Types::CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT,
              uniqueItems: true,
              description: "A Candidate covers at most 32 leased resources. Split larger work into separate WorkItems.",
              items: candidate_manifest_file
            }
          },
          required: %w[collector_version files]
        )
      end

      def candidate_manifest_file
        nullable_oid = { anyOf: [ git_oid, { type: "null" } ] }
        nullable_path = {
          anyOf: [ { type: "string", minLength: 1, maxLength: 1_024 }, { type: "null" } ]
        }
        nullable_mode = {
          anyOf: [ { type: "string", enum: Types::CANDIDATE_GIT_FILE_MODES }, { type: "null" } ]
        }
        object_schema(
          properties: {
            status: { type: "string", enum: Types::CANDIDATE_MANIFEST_STATUSES },
            old_path: nullable_path,
            new_path: nullable_path,
            old_blob_oid: nullable_oid,
            new_blob_oid: nullable_oid,
            old_mode: nullable_mode,
            new_mode: nullable_mode
          },
          required: %w[status]
        )
      end

      def candidate_build_context
        input = object_schema(
          properties: {
            kind: { type: "string", enum: Types::CANDIDATE_BUILD_INPUT_KINDS },
            path: { type: "string", minLength: 1, maxLength: 1_024 },
            blob_oid: git_oid
          },
          required: %w[kind path blob_oid]
        )
        environment = object_schema(
          properties: {
            name: { type: "string", minLength: 1, maxLength: 100 },
            value: { type: "string", minLength: 1, maxLength: 500 }
          },
          required: %w[name value]
        )
        object_schema(
          properties: {
            collector_version: { type: "string", minLength: 1, maxLength: 100 },
            inputs: { type: "array", maxItems: 64, uniqueItems: true, items: input },
            environment: {
              type: "array", maxItems: 32, uniqueItems: true, items: environment
            },
            dependency_graph_digest: nullable_sha256_digest,
            test_environment_digest: nullable_sha256_digest
          },
          required: %w[collector_version inputs environment]
        )
      end

      def candidate_impact_surface
        object_schema(
          properties: {
            produces: {
              type: "array",
              maxItems: 64,
              uniqueItems: true,
              items: object_schema(
                properties: {
                  impact_key: candidate_impact_key,
                  before: nullable_candidate_impact_value,
                  after: candidate_impact_value
                },
                required: %w[impact_key after]
              )
            },
            consumes: {
              type: "array",
              maxItems: 64,
              uniqueItems: true,
              items: object_schema(
                properties: {
                  impact_key: candidate_impact_key,
                  value: candidate_impact_value
                },
                required: %w[impact_key value]
              )
            },
            may_affect: {
              type: "array",
              maxItems: 64,
              uniqueItems: true,
              items: object_schema(
                properties: { impact_key: candidate_impact_key },
                required: %w[impact_key]
              )
            },
            assumes: {
              type: "array",
              maxItems: 64,
              uniqueItems: true,
              items: object_schema(
                properties: {
                  impact_key: candidate_impact_key,
                  predicate: candidate_impact_value
                },
                required: %w[impact_key predicate]
              )
            }
          },
          required: %w[produces consumes may_affect assumes]
        )
      end

      def candidate_impact_key
        {
          type: "string",
          minLength: 3,
          maxLength: 200,
          pattern: "^[a-z][a-z0-9_.-]*(?::[a-z0-9][a-z0-9_.-]*)+$"
        }
      end

      def candidate_impact_value
        { type: "string", minLength: 1, maxLength: 500 }
      end

      def nullable_candidate_impact_value
        { anyOf: [ candidate_impact_value, { type: "null" } ] }
      end

      def nullable_sha256_digest
        {
          anyOf: [
            { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            { type: "null" }
          ]
        }
      end

      def interpretation_source_span
        object_schema(
          properties: {
            start_character: { type: "integer", minimum: 0 },
            end_character: { type: "integer", minimum: 0 },
            text: { type: "string", minLength: 1, maxLength: 16_000 }
          },
          required: %w[start_character end_character text]
        )
      end

      def interpretation_classifier
        object_schema(
          properties: {
            id: identifier,
            version: { type: "string", minLength: 1, maxLength: 200 },
            ontology_version: { type: "integer", const: 1 },
            confidence_millionths: { type: "integer", minimum: 0, maximum: 1_000_000 }
          },
          required: %w[id version ontology_version confidence_millionths]
        )
      end

      def interpretation_decision
        object_schema(
          properties: {
            statement_kind: { type: "string", enum: Types::STATEMENT_KINDS },
            topic_id: identifier,
            effect: nullable_enum(Types::DECISION_EFFECTS),
            modality: nullable_enum(Types::DECISION_MODALITIES),
            value: interpretation_value,
            scope: { anyOf: [ interpretation_scope, { type: "null" } ] },
            conditions: interpretation_conditions,
            validity: interpretation_validity,
            authority: object_schema(
              properties: { actor_id: identifier, role: identifier },
              required: %w[actor_id role]
            ),
            enforcement: object_schema(
              properties: {
                level: { type: "string", enum: Types::ENFORCEMENT_LEVELS },
                retroactivity: { type: "string", enum: Types::RETROACTIVITY_KINDS },
                on_violation: { type: "string", enum: Types::VIOLATION_ACTIONS }
              },
              required: %w[level retroactivity on_violation]
            ),
            relations: interpretation_relations
          },
          required: %w[
            statement_kind topic_id effect modality value scope conditions validity
            authority enforcement relations
          ]
        )
      end

      def interpretation_value
        object_schema(
          properties: {
            schema: { type: "string", enum: Types::DECISION_VALUE_SCHEMAS },
            name: nullable_string,
            items: {
              anyOf: [ string_array(min_items: 1, max_items: 100, max_length: 200), { type: "null" } ]
            },
            target_kind: nullable_enum(Types::MERGE_TARGET_KINDS),
            target_id: nullable_identifier,
            action: nullable_enum(Types::MERGE_ACTIONS)
          },
          required: %w[schema name items target_kind target_id action]
        )
      end

      def interpretation_scope
        properties = {
          workspace_id: nullable_identifier,
          repository_ids: {
            type: "array",
            maxItems: 100,
            uniqueItems: true,
            items: uuid_v7
          },
          branch_selectors: identifier_array,
          change_set_id: nullable_identifier,
          work_item_id: nullable_identifier,
          attempt_id: nullable_identifier,
          candidate_id: nullable_identifier,
          path_selectors: string_array(min_items: 0, max_items: 100, max_length: 1_024),
          symbol_selectors: identifier_array,
          contract_selectors: identifier_array,
          schema_selectors: identifier_array,
          environments: identifier_array,
          agent_roles: identifier_array
        }
        object_schema(properties:, required: properties.keys.map(&:to_s))
      end

      def interpretation_conditions
        properties = {
          phases: {
            type: "array",
            maxItems: 5,
            uniqueItems: true,
            items: { type: "string", enum: Types::DECISION_PHASES }
          },
          languages: identifier_array,
          tags: identifier_array,
          repository_kinds: identifier_array,
          artifact_kinds: identifier_array,
          environments: identifier_array
        }
        object_schema(properties:, required: properties.keys.map(&:to_s))
      end

      def interpretation_validity
        until_event = object_schema(
          properties: {
            event_type: identifier,
            stream_context: identifier,
            stream_name: identifier,
            stream_id: identifier
          },
          required: %w[event_type stream_context stream_name stream_id]
        )
        object_schema(
          properties: {
            valid_from: nullable_string,
            valid_until: nullable_string,
            until_event: { anyOf: [ until_event, { type: "null" } ] }
          },
          required: %w[valid_from valid_until until_event]
        )
      end

      def interpretation_relations
        properties = {
          corrects: identifier_array(max_items: 20),
          supersedes: identifier_array(max_items: 20),
          exception_to: identifier_array(max_items: 20),
          revokes: identifier_array(max_items: 20)
        }
        object_schema(properties:, required: properties.keys.map(&:to_s))
      end

      def interpretation_ambiguity
        object_schema(
          properties: {
            field: identifier,
            code: identifier,
            description: { type: "string", minLength: 1, maxLength: 500 },
            options: string_array(min_items: 0, max_items: 10, max_length: 200)
          },
          required: %w[field code description options]
        )
      end

      def interpretation_question
        object_schema(
          properties: {
            field: identifier,
            prompt: { type: "string", minLength: 1, maxLength: 500 },
            options: string_array(min_items: 0, max_items: 10, max_length: 200)
          },
          required: %w[field prompt options]
        )
      end

      def identifier_array(max_items: 100)
        {
          type: "array",
          maxItems: max_items,
          uniqueItems: true,
          items: identifier
        }
      end

      def nullable_enum(values)
        { anyOf: [ { type: "string", enum: values }, { type: "null" } ] }
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
