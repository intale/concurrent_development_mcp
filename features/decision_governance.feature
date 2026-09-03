@event-contract
Feature: Decision governance
  Accepted interpretations become normative only through explicit authoritative commands.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Accepted interpretations become policy only through explicit activation

    @CDM-DECISION-001 @stale-view
    Scenario: Available Decision evidence converges after the activation Task commits
      Given these interpretations are accepted for activation:
        | interpretation_id | message_id     | decision_id    |
        | I-CUC-DEC-1       | M-CUC-DEC-1    | D-CUC-DEC-1    |
      Then acceptance has emitted no Decision facts
      When the host activates interpretation "I-CUC-DEC-1" as Decision "D-CUC-DEC-1" through a Task
      Then the activation Task succeeds with one complete consistency boundary
      And Decision "D-CUC-DEC-1" is honestly not observed before projection
      When the remaining facts for Decision "D-CUC-DEC-1" reach the read side
      Then the available Decision "D-CUC-DEC-1" is active without a freshness claim

    @CDM-DECISION-002 @concurrency
    Scenario: Concurrent activation of one normative slot has one winner
      Given these interpretations are accepted for activation:
        | interpretation_id | message_id     | decision_id    |
        | I-CUC-DEC-A       | M-CUC-DEC-A    | D-CUC-DEC-A    |
        | I-CUC-DEC-B       | M-CUC-DEC-B    | D-CUC-DEC-B    |
      Then acceptance has emitted no Decision facts
      When the host concurrently activates all accepted interpretations through Tasks
      Then one activation Task succeeds and the other reports an occupied Decision slot
      And the losing activation writes no Decision facts and records its command rejection

  Rule: An active Decision is corrected from accepted evidence against its authoritative head

    @CDM-DECISION-003 @stale-view
    Scenario: A stale available Decision remains readable but cannot overwrite a completed correction
      Given these interpretations are accepted for activation:
        | interpretation_id | message_id     | decision_id    |
        | I-CUC-COR-BASE     | M-CUC-COR-BASE | D-CUC-COR-1    |
      When the host activates interpretation "I-CUC-COR-BASE" as Decision "D-CUC-COR-1" through a Task
      Then the activation Task succeeds with one complete consistency boundary
      When the remaining facts for Decision "D-CUC-COR-1" reach the read side
      Given these correction interpretations are accepted for Decision "D-CUC-COR-1":
        | interpretation_id | message_id       | value     |
        | I-CUC-COR-1       | M-CUC-COR-1      | minitest  |
        | I-CUC-COR-STALE   | M-CUC-COR-STALE  | test-unit |
      When the host corrects Decision "D-CUC-COR-1" with interpretation "I-CUC-COR-1" using the available head
      Then the correction Task succeeds while the previous Decision view remains available
      When the host corrects Decision "D-CUC-COR-1" with interpretation "I-CUC-COR-STALE" using the same stale head
      Then the stale correction Task reports a Decision revision conflict without new policy facts
      When the correction fact for Decision "D-CUC-COR-1" reaches the read side
      Then the available Decision "D-CUC-COR-1" exposes correction interpretation "I-CUC-COR-1" without a freshness claim
