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

      def guidance_record
        anchors = object_schema(
          properties: {
            repository_ids: {
              type: "array",
              items: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
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
            repository_id: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
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
          change_set_id candidate_id work_item_id repository_id kind enforcement status
        ]
        object_schema(
          properties: {
            change_set_id: nullable_identifier,
            candidate_id: nullable_identifier,
            work_item_id: nullable_identifier,
            repository_id: {
              type: [ "string", "null" ],
              pattern: "^[a-z0-9][a-z0-9._-]{0,99}$"
            },
            kind: nullable_enum([ "candidate_compatibility" ]),
            enforcement: nullable_enum(%w[verification_gate merge_gate]),
            status: nullable_enum([ "open" ]),
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

      def candidate_impact_surface_submit
        object_schema(
          properties: common_mutation_properties.merge(
            candidate_id: identifier,
            repository_id: {
              type: "string",
              pattern: "^[a-z0-9][a-z0-9._-]{0,99}$"
            },
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

      def decision_resolve
        object_schema(
          properties: {
            topic_id: { type: "string", const: "testing.framework" },
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

      def agent_actor
        object_schema(
          properties: {
            kind: { type: "string", const: "agent" },
            id: identifier
          },
          required: %w[kind id]
        )
      end

      def decision_query_context(require_nullable_fields: false)
        required = %w[
          repository_id change_set_id work_item_id attempt_id phase language paths agent_role
        ]
        required += %w[workspace_id environment] if require_nullable_fields
        object_schema(
          properties: {
            workspace_id: nullable_identifier,
            repository_id: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" },
            change_set_id: identifier,
            work_item_id: identifier,
            attempt_id: identifier,
            phase: { type: "string", const: "implementation" },
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
            resolution_policy: { type: "string", const: "testing-framework-resolution/v1" },
            topic_id: { type: "string", const: "testing.framework" },
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
                topic_root: { type: "string", const: "testing" },
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
            topic_id: { type: "string", const: "testing.framework" },
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

      def candidate_change_manifest
        object_schema(
          properties: {
            collector_version: { type: "string", minLength: 1, maxLength: 100 },
            files: {
              type: "array",
              minItems: 1,
              maxItems: 256,
              uniqueItems: true,
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
            items: { type: "string", pattern: "^[a-z0-9][a-z0-9._-]{0,99}$" }
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
