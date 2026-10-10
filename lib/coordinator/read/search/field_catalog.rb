# frozen_string_literal: true

module Coordinator::Read::Search
  module FieldCatalog
    # These are projection paths, not caller-controlled SQL identifiers. JSON
    # collections yield individual raw strings, never serialized documents.
    DEFINITIONS = {
      "skill" => [ "skills/current skill_revisions", "skill_get", {
        "name" => [ "name" ], "scope" => [ "scope" ],
        "description" => [ "description" ], "instructions" => [ "instructions" ]
      } ],
      "skill_asset" => [ "skill_assets", "skill_asset_get", {
        "path" => [ "path" ], "content" => [ "content_text" ]
      } ],
      "resource" => [ "resources", "resource_get", {
        "path" => [ "normalized_path" ], "kind" => [ "kind" ],
        "unbinding_reason" => [ "unbinding_reason" ]
      } ],
      "development_artifact" => [ "development_artifacts/development_artifact_observations", "development_artifact_content_get", {
        "title" => [ "title" ], "scope" => [ "scope" ], "kind" => [ "kind" ],
        "labels" => [ "labels", [], "elements" ], "content" => [ "content_text" ],
        "source_locator" => [ "source_locator" ], "source_revision" => [ "source_revision" ],
        "source_collector" => [ "source_collector" ], "classification_reason" => [ "classification_reason" ]
      } ],
      "guidance" => [ "user_utterances", "guidance_get", { "text" => [ "text" ] } ],
      "agent_choice" => [ "agent_choices", "agent_choice_get", {
        "choice_type" => [ "choice_type" ], "reason_summary" => [ "reason_summary" ],
        "selected_summary" => [ "selected", [ "summary" ] ],
        "alternative_summary" => [ "alternatives", [ "*", "summary" ], "scalar" ],
        "warnings" => [ "assessment", [ "warnings" ], "elements" ],
        "invalidation_reason" => [ "invalidation", [ "reason" ] ]
      } ],
      "decision" => [ "decision_definitions", "decision_get", {
        "topic" => [ "definition", [ "document", "topic", "topic_id" ] ],
        "topic_aliases" => [ "definition", [ "document", "topic", "aliases" ], "elements" ],
        "value_name" => [ "definition", [ "document", "value", "name" ] ],
        "value_items" => [ "definition", [ "document", "value", "items" ], "elements" ],
        "value_action" => [ "definition", [ "document", "value", "action" ] ],
        "value_target_id" => [ "definition", [ "document", "value", "target_id" ] ],
        "scope" => [ "definition", [ "document", "scope" ], "strings" ],
        "conditions" => [ "definition", [ "document", "conditions" ], "strings" ],
        "rationale" => [ "rationale", [ "summary" ] ],
        "correction_rationale" => [ "correction_rationale", [ "summary" ] ]
      } ],
      "work_item" => [ "coordinator_contexts.document.work_items", "coord_context", {
        "goal" => [ "goal" ], "acceptance_criteria" => [ "acceptance_criteria", [], "elements" ]
      } ]
    }.freeze

    FIELDS = DEFINITIONS.flat_map do |entity_type, (source, retrieval_tool, definitions)|
      definitions.map do |name, (column, path, values)|
        Field.new(selector: "#{entity_type}.#{name}", entity_type:, source:,
          column:, path: path || [], values: values || "scalar", retrieval_tool:)
      end
    end.to_h { [ _1.selector, _1 ] }.freeze
    SELECTORS = FIELDS.keys.freeze
    ENTITY_TYPES = DEFINITIONS.keys.freeze

    def self.fetch(selector)
      FIELDS.fetch(selector)
    end
  end
end
