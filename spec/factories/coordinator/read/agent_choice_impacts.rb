# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_agent_choice_impact, class: "Coordinator::Read::AgentChoiceImpact" do
    assessment_id { SecureRandom.uuid_v7 }
    sequence(:choice_id) { "CHO-factory-impact-#{_1}" }
    sequence(:attempt_id) { "A-factory-impact-#{_1}" }
    outcome { "invalidated" }
    reason { "blocking_policy_introduced" }
    policy_version { "agent-choice-decision-impact/v1" }
    accepted_choice do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "AgentChoiceAccepted",
        "stream_context" => "AgentGovernance",
        "stream_name" => "AgentChoice",
        "stream_id" => choice_id,
        "stream_revision" => 1
      }
    end
    decision_change do
      {
        "source_event" => {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "DecisionDefinitionCorrected",
          "stream_context" => "HumanGuidance",
          "stream_name" => "Decision",
          "stream_id" => "D-#{choice_id}",
          "stream_revision" => 2
        },
        "source_global_position" => 40,
        "source_command_id" => "cmd-correct-#{choice_id}",
        "source_actor" => { "kind" => "orchestrator", "id" => "guidance-host" },
        "decision_id" => "D-#{choice_id}",
        "change_kind" => "corrected",
        "definition_digest" => "sha256:#{'d' * 64}",
        "retroactivity" => "all_unmerged_candidates",
        "affected_partitions" => [
          {
            "partition_id" => "testing:attempt:#{attempt_id}",
            "topic_root" => "testing",
            "anchor_kind" => "attempt",
            "anchor_id" => attempt_id
          }
        ],
        "changed_at" => "2026-08-30T11:59:00.000000Z"
      }
    end
    assessment do
      head = {
        "decision_id" => decision_change.fetch("decision_id"),
        "decision_revision" => 2,
        "event" => decision_change.fetch("source_event")
      }
      evaluation = {
        "status" => "allowed",
        "effective_decision" => head,
        "contributing_decisions" => [ head ],
        "basis" => "compliant",
        "warnings" => [],
        "reason_codes" => [ "selected_option_satisfies_decision" ]
      }
      {
        "before_evaluation" => evaluation,
        "after_evaluation" => evaluation.merge(
          "status" => "blocked",
          "basis" => "blocking_violation",
          "reason_codes" => [ "selected_option_violates_blocking_decision" ]
        ),
        "outcome" => outcome,
        "reason" => reason
      }
    end
    assessment_event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "AgentChoiceImpactAssessmentRecorded",
        "stream_context" => "AgentGovernance",
        "stream_name" => "AgentChoiceImpact",
        "stream_id" => assessment_id,
        "stream_revision" => 0
      }
    end
    source_actor { { "kind" => "orchestrator", "id" => "guidance-host", "authenticated" => false } }
    assessment_actor { { "kind" => "system", "id" => "choice-impact", "authenticated" => false } }
    markers { [ "choice:#{choice_id}" ] }
    metadata { { "schema_version" => 1 } }
    sequence(:event_global_position, 700)
    assessed_at_domain { Time.utc(2026, 8, 30, 12) }
    assessed_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }
  end
end
