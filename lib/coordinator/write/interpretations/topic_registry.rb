# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class TopicRegistry
      DEFINITIONS = [
        TopicDefinitionV1.new(
          topic_id: "testing.framework",
          parent_topic_id: "testing",
          value_schema: "named-choice/v1",
          resolution_strategy: "single_choice",
          inheritable: true,
          default_modality: "should",
          default_enforcement: "implementation_gate",
          conflict_dimension: "primary_test_framework",
          ontology_version: 1,
          aliases: []
        ),
        TopicDefinitionV1.new(
          topic_id: "testing.required_suites",
          parent_topic_id: "testing",
          value_schema: "string-set/v1",
          resolution_strategy: "set_union",
          inheritable: true,
          default_modality: "must",
          default_enforcement: "verification_gate",
          conflict_dimension: "required_suite",
          ontology_version: 1,
          aliases: []
        ),
        TopicDefinitionV1.new(
          topic_id: "implementation.dependencies.forbidden",
          parent_topic_id: "implementation.dependencies",
          value_schema: "string-set/v1",
          resolution_strategy: "set_union",
          inheritable: true,
          default_modality: "must_not",
          default_enforcement: "implementation_gate",
          conflict_dimension: "forbidden_dependency",
          ontology_version: 1,
          aliases: []
        ),
        TopicDefinitionV1.new(
          topic_id: "delivery.merge",
          parent_topic_id: "delivery",
          value_schema: "target-action/v1",
          resolution_strategy: "manual_resolution",
          inheritable: false,
          default_modality: "must",
          default_enforcement: "merge_gate",
          conflict_dimension: "merge_disposition",
          ontology_version: 1,
          aliases: []
        )
      ].to_h { [ _1.topic_id, _1 ] }.freeze

      def fetch(topic_id)
        DEFINITIONS[topic_id]
      end
    end
  end
end
