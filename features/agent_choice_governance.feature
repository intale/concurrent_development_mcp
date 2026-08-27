@event-contract
Feature: Agent choice governance
  Significant agent choices are authoritative Tasks and Decision changes assess their continued validity.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Significant agent choices are authoritative Tasks with available evidence

    @CDM-CHOICE-001 @stale-view
    Scenario: An accepted testing-framework choice converges through the production read subscription
      Given agent "agent-a" has active Attempt "A-CUC-CHO-1" for WorkItem "W-CUC-CHO-1" in ChangeSet "CS-CUC-CHO-1" and repository "billing"
      When the agent resolves the available testing-framework context
      And the agent records testing-framework choice "rspec" as "CHO-CUC-1" through a Task
      Then the choice Task succeeds with accepted authoritative facts
      And AgentChoice "CHO-CUC-1" is honestly not observed before projection
      When the AgentChoiceAccepted fact for "CHO-CUC-1" reaches the read side
      Then the available AgentChoice "CHO-CUC-1" is accepted without a freshness claim

    @CDM-STALE-001 @stale-view
    Scenario: An older available context is served while authoritative choice recording rejects it
      Given agent "agent-a" has active Attempt "A-CUC-CHO-STALE" for WorkItem "W-CUC-CHO-STALE" in ChangeSet "CS-CUC-CHO-STALE" and repository "billing"
      When the agent resolves the available testing-framework context
      Given these interpretations are accepted for activation:
        | interpretation_id | message_id        | decision_id        |
        | I-CUC-CHO-STALE   | M-CUC-CHO-STALE  | D-CUC-CHO-STALE   |
      When the host activates interpretation "I-CUC-CHO-STALE" as Decision "D-CUC-CHO-STALE" through a Task
      Then the activation Task succeeds with one complete consistency boundary
      And the older Decision context remains available without a freshness claim
      When the agent records testing-framework choice "rspec" as "CHO-CUC-STALE" through a Task
      Then the choice Task reports stale context and explains how to refresh
      And the stale choice writes no AgentChoice or command facts
      When the agent follows the refresh action for the current Decision context
      Then the current testing-framework policy is available
      When the agent records testing-framework choice "rspec" as "CHO-CUC-REFRESHED" through a Task
      Then the choice Task succeeds with accepted authoritative facts

  Rule: Decision changes assess accepted choices through an internal resumable Saga

    @CDM-IMPACT-001 @stale-view
    Scenario: Impact evidence is available before the terminal Choice projection catches up
      Given agent "agent-a" has active Attempt "A-CUC-IMPACT-1" for WorkItem "W-CUC-IMPACT-1" in ChangeSet "CS-CUC-IMPACT-1" and repository "billing"
      When the agent resolves the available testing-framework context
      And the agent records testing-framework choice "rspec" as "CHO-CUC-IMPACT-1" through a Task
      Then the choice Task succeeds with accepted authoritative facts
      When the accepted AgentChoice "CHO-CUC-IMPACT-1" reaches the read side
      And the host activates active-attempt Decision "D-CUC-IMPACT-1" requiring "minitest" through Tasks
      And the impact Saga processes and redrives the Decision change
      Then one invalidating assessment and one terminal invalidation are durable for "CHO-CUC-IMPACT-1"
      When the impact assessment for "CHO-CUC-IMPACT-1" reaches the read side
      Then Attempt "A-CUC-IMPACT-1" exposes the invalidating assessment and AgentChoice "CHO-CUC-IMPACT-1" is invalidated
      And AgentChoice "CHO-CUC-IMPACT-1" is invalidated and tells the agent to resolve current Decisions

    @CDM-IMPACT-002
    Scenario: A compatible correction records an explicit still-valid assessment
      Given agent "agent-a" has active Attempt "A-CUC-IMPACT-VALID" for WorkItem "W-CUC-IMPACT-VALID" in ChangeSet "CS-CUC-IMPACT-VALID" and repository "billing"
      And active-attempt Decision "D-CUC-IMPACT-VALID" requiring "rspec" is active and available
      When the agent resolves the available testing-framework context
      And the agent records testing-framework choice "rspec" as "CHO-CUC-IMPACT-VALID" through a Task
      Then the choice Task succeeds with accepted authoritative facts
      When the accepted AgentChoice "CHO-CUC-IMPACT-VALID" reaches the read side
      And the host corrects Decision "D-CUC-IMPACT-VALID" to advisory active-attempt choice "rspec" through Tasks
      And the impact Saga processes and redrives the Decision change
      Then one still-valid assessment and no invalidation are durable for "CHO-CUC-IMPACT-VALID"
      When the impact assessment for "CHO-CUC-IMPACT-VALID" reaches the read side
      Then Attempt "A-CUC-IMPACT-VALID" exposes a still-valid assessment and AgentChoice "CHO-CUC-IMPACT-VALID" remains accepted

    @CDM-IMPACT-003
    Scenario: Redelivery is idempotent and impact pages contain every assessment once
      Given agent "agent-a" has active Attempt "A-CUC-IMPACT-PAGE" for WorkItem "W-CUC-IMPACT-PAGE" in ChangeSet "CS-CUC-IMPACT-PAGE" and repository "billing"
      When the agent resolves the available testing-framework context
      And the agent records 3 testing-framework choices starting at "CHO-CUC-IMPACT-PAGE" through Tasks
      Then all impact-test choices have accepted authoritative facts
      When all impact-test AgentChoices reach the read side
      And the host activates active-attempt Decision "D-CUC-IMPACT-PAGE" requiring "minitest" through Tasks
      And the impact Saga processes and redrives the Decision change
      Then every impact-test Choice has one assessment and one invalidation
      When all impact-test assessments reach the read side
      Then the agent retrieves every impact once in two-item pages for Attempt "A-CUC-IMPACT-PAGE"
