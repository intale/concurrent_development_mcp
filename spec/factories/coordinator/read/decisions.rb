# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_decision_definition, class: "Coordinator::Read::DecisionDefinition" do
    transient do
      repository_id { "018f0f4d-4e45-7abc-8def-000000000099" }
      change_set_id { nil }
      work_item_id { nil }
      attempt_id { nil }
      candidate_id { nil }
      topic_id { "testing.framework" }
      enforcement_level { "implementation_gate" }
      required_evidence { %w[combined_tests] }
    end

    sequence(:decision_id) { "D-factory-#{_1}" }
    interpretation_id { "I-#{decision_id}" }
    source_message_id { "M-#{decision_id}" }
    policy_status { "recorded" }
    definition_digest { "sha256:#{'d' * 64}" }
    definition do
      candidate_policy = topic_id == "candidate.impact_policy"
      scope = {
        "workspace_id" => nil,
        "repository_ids" => candidate_policy || repository_id.nil? ? [] : [ repository_id ],
        "branch_selectors" => [],
        "change_set_id" => candidate_policy ? change_set_id : nil,
        "work_item_id" => work_item_id,
        "attempt_id" => attempt_id,
        "candidate_id" => candidate_id,
        "path_selectors" => [],
        "symbol_selectors" => [],
        "contract_selectors" => [],
        "schema_selectors" => [],
        "environments" => [],
        "agent_roles" => []
      }
      topic = if candidate_policy
        {
          "topic_id" => topic_id,
          "parent_topic_id" => "candidate.impact",
          "value_schema" => "string-set/v1",
          "resolution_strategy" => "single_choice",
          "inheritable" => false,
          "default_modality" => "must",
          "default_enforcement" => "disabled",
          "conflict_dimension" => "candidate_impact_policy",
          "ontology_version" => 1,
          "aliases" => []
        }
      else
        {
          "topic_id" => topic_id,
          "parent_topic_id" => "testing",
          "value_schema" => "named-choice/v1",
          "resolution_strategy" => "single_choice",
          "inheritable" => true,
          "default_modality" => "should",
          "default_enforcement" => "implementation_gate",
          "conflict_dimension" => "primary_test_framework",
          "ontology_version" => 1,
          "aliases" => []
        }
      end
      value = if candidate_policy
        {
          "schema" => "string-set/v1",
          "name" => nil,
          "items" => required_evidence,
          "target_kind" => nil,
          "target_id" => nil,
          "action" => nil
        }
      else
        {
          "schema" => "named-choice/v1",
          "name" => "rspec",
          "items" => nil,
          "target_kind" => nil,
          "target_id" => nil,
          "action" => nil
        }
      end
      {
        "document" => {
          "schema" => "decision-definition/v1",
          "statement_kind" => candidate_policy ? "directive" : "preference",
          "topic" => topic,
          "effect" => candidate_policy ? "require" : "prefer",
          "modality" => candidate_policy ? "must" : "should",
          "value" => value,
          "scope" => scope,
          "conditions" => {
            "phases" => candidate_policy ? [] : [ "implementation" ],
            "languages" => candidate_policy ? [] : [ "ruby" ],
            "tags" => [],
            "repository_kinds" => [],
            "artifact_kinds" => [],
            "environments" => []
          },
          "validity" => {
            "valid_from" => "2026-08-30T12:00:00.000000Z",
            "valid_until" => nil,
            "until_event" => nil
          },
          "authority" => { "actor_id" => "factory-user", "role" => "project-owner" },
          "enforcement" => {
            "level" => enforcement_level,
            "retroactivity" => candidate_policy ? "all_unmerged_candidates" : "future_only",
            "on_violation" => enforcement_level == "advisory" ? "warn" : "block"
          },
          "relations" => { "corrects" => [], "supersedes" => [], "exception_to" => [], "revokes" => [] }
        },
        "digest" => definition_digest
      }
    end
    slot { nil }
    partitions { [] }
    classifier do
      {
        "id" => "factory-classifier",
        "version" => "decision-classifier-v1",
        "ontology_version" => 1,
        "confidence_millionths" => 940_000
      }
    end
    scope_provenance do
      {
        "kind" => "explicit",
        "anchor_level" => change_set_id ? "change_set" : "repository",
        "source_message_id" => source_message_id
      }
    end
    source_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "UserUtteranceRecorded",
        "stream_context" => "DevelopmentGuidance",
        "stream_name" => "Conversation",
        "stream_id" => "C-#{decision_id}",
        "stream_revision" => 0
      }
    end
    proposal_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DecisionInterpretationProposed",
        "stream_context" => "HumanGuidance",
        "stream_name" => "DecisionInterpretation",
        "stream_id" => source_message_id,
        "stream_revision" => 0
      }
    end
    acceptance_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DecisionInterpretationAccepted",
        "stream_context" => "HumanGuidance",
        "stream_name" => "DecisionInterpretation",
        "stream_id" => source_message_id,
        "stream_revision" => 1
      }
    end
    recorded_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DecisionRecorded",
        "stream_context" => "HumanGuidance",
        "stream_name" => "Decision",
        "stream_id" => decision_id,
        "stream_revision" => 0
      }
    end
    recorded_actor { { "kind" => "orchestrator", "id" => "guidance-host", "authenticated" => false } }
    recorded_markers { [ "decision:#{decision_id}" ] }
    recorded_metadata { { "schema_version" => 1 } }
    recorded_at_domain { Time.utc(2026, 8, 30, 12) }
    recorded_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }

    trait :active do
      policy_status { "active" }
      partitions do
        [
          {
            "partition_id" => topic_id == "candidate.impact_policy" ?
              "changeset:#{change_set_id}:candidate" : "testing:repo:#{repository_id}",
            "topic_root" => topic_id.split(".").first,
            "anchor_kind" => topic_id == "candidate.impact_policy" ? "changeset" : "repo",
            "anchor_id" => topic_id == "candidate.impact_policy" ? change_set_id : repository_id
          }
        ]
      end
      slot do
        scope = definition.fetch("document").fetch("scope")
        conditions = definition.fetch("document").fetch("conditions")
        marker_digest = "sha256:#{'e' * 64}"
        {
          "slot_id" => "slot-#{decision_id}",
          "document" => {
            "schema" => "decision-slot/v1",
            "topic_id" => topic_id,
            "exact_scope" => scope,
            "exact_conditions" => conditions,
            "conflict_dimension" => topic_id == "candidate.impact_policy" ?
              "candidate_impact_policy" : "primary_test_framework",
            "resolution_strategy" => "single_choice"
          },
          "compound_marker" => {
            "purpose" => "decision-slot",
            "components" => [ "topic:#{topic_id}", "decision:#{decision_id}" ],
            "digest" => marker_digest,
            "marker" => "compound:decision-slot:v1:#{marker_digest}"
          }
        }
      end
      rationale { { "code" => "user_confirmed", "summary" => "Activate the accepted policy." } }
      activated_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "DecisionActivated",
          "stream_context" => "HumanGuidance",
          "stream_name" => "Decision",
          "stream_id" => decision_id,
          "stream_revision" => 1
        }
      end
      activated_actor { recorded_actor }
      activated_markers { recorded_markers }
      activated_metadata { { "schema_version" => 1 } }
      activated_at_domain { Time.utc(2026, 8, 30, 12, 1) }
      activated_at_store { Time.utc(2026, 8, 30, 12, 1, 1) }
    end
  end

  factory :coordinator_read_decision_interpretation,
          class: "Coordinator::Read::DecisionInterpretation" do
    sequence(:interpretation_id) { "I-factory-#{_1}" }
    sequence(:message_id) { "M-factory-interpretation-#{_1}" }
    source_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "UserUtteranceRecorded",
        "stream_context" => "DevelopmentGuidance",
        "stream_name" => "Conversation",
        "stream_id" => "C-#{message_id}",
        "stream_revision" => 0
      }
    end
    source_span { { "start_character" => 4, "end_character" => 9, "text" => "RSpec" } }
    classifier do
      {
        "id" => "factory-classifier",
        "version" => "decision-classifier-v1",
        "ontology_version" => 1,
        "confidence_millionths" => 940_000
      }
    end
    proposed_decision do
      {
        "statement_kind" => "preference",
        "topic_id" => "testing.framework",
        "effect" => "prefer",
        "modality" => "should",
        "value" => {
          "schema" => "named-choice/v1", "name" => "rspec", "items" => nil,
          "target_kind" => nil, "target_id" => nil, "action" => nil
        },
        "scope" => {
          "workspace_id" => nil, "repository_ids" => [], "branch_selectors" => [],
          "change_set_id" => "CS-factory", "work_item_id" => nil, "attempt_id" => nil,
          "candidate_id" => nil, "path_selectors" => [], "symbol_selectors" => [],
          "contract_selectors" => [], "schema_selectors" => [], "environments" => [],
          "agent_roles" => []
        },
        "conditions" => {
          "phases" => [ "implementation" ], "languages" => [ "ruby" ], "tags" => [],
          "repository_kinds" => [], "artifact_kinds" => [], "environments" => []
        },
        "validity" => { "valid_from" => nil, "valid_until" => nil, "until_event" => nil },
        "authority" => { "actor_id" => "factory-user", "role" => "project-owner" },
        "enforcement" => {
          "level" => "advisory", "retroactivity" => "future_only", "on_violation" => "warn"
        },
        "relations" => { "corrects" => [], "supersedes" => [], "exception_to" => [], "revokes" => [] }
      }
    end
    scope_provenance do
      { "kind" => "explicit", "anchor_level" => "change_set", "source_message_id" => message_id }
    end
    ambiguities { [] }
    assessment { { "status" => "accepted_for_activation", "reasons" => [], "questions" => [] } }
    proposal_status { assessment.fetch("status") }
    lifecycle_status { "proposed" }
    policy_status { "proposal_only" }
    adjudication { nil }
    clarification_required { false }
    actor_kind { "agent" }
    actor_id { "factory-classifier" }
    event_id { SecureRandom.uuid_v7 }
    event_type { "DecisionInterpretationProposed" }
    stream_context { "HumanGuidance" }
    stream_name { "DecisionInterpretation" }
    stream_id { message_id }
    sequence(:stream_revision, 0)
    proposed_at_domain { Time.utc(2026, 8, 30, 12) }
  end

  factory :coordinator_read_decision_partition_head,
          class: "Coordinator::Read::DecisionPartitionHead" do
    sequence(:partition_id) { "changeset:CS-factory-#{_1}:candidate" }
    sequence(:decision_id) { "D-factory-policy-#{_1}" }
    partition do
      {
        "partition_id" => partition_id,
        "topic_root" => "candidate",
        "anchor_kind" => "changeset",
        "anchor_id" => partition_id.split(":").fetch(1)
      }
    end
    partition_revision { 0 }
    decision do
      {
        "decision_id" => decision_id,
        "decision_revision" => 1,
        "event" => {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "DecisionActivated",
          "stream_context" => "HumanGuidance",
          "stream_name" => "Decision",
          "stream_id" => decision_id,
          "stream_revision" => 1
        }
      }
    end
    active_decisions { [ decision ] }
    change_kind { "activated" }
    event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "DecisionPartitionAdvanced",
        "stream_context" => "HumanGuidance",
        "stream_name" => "DecisionPartition",
        "stream_id" => partition_id,
        "stream_revision" => partition_revision
      }
    end
    actor { { "kind" => "orchestrator", "id" => "guidance-host", "authenticated" => false } }
    markers { [ "partition:#{partition_id}" ] }
    metadata { { "schema_version" => 1 } }
    advanced_at_domain { Time.utc(2026, 8, 30, 12) }
    event_created_at { Time.utc(2026, 8, 30, 12, 0, 1) }
  end
end
