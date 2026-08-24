@merge_snapshot
Feature: Attributed merge snapshot registration
  Agents checkpoint an externally produced composition through a durable Task.
  The write side protects immutable evidence while the read side remains available during lag.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Scenario: Registration is authoritative while its available projection converges later
    Given Candidate coordination "MERGE-SNAPSHOT" gives agent "agent-a" an active lease on "lib/merge_snapshot.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-SNAPSHOT" with command "cmd-cuc-merge-candidate" at head "b" without build context
    Then the Candidate Task completes with an attributed unverified checkpoint
    When the agent registers merge snapshot "MS-CUC-MERGE-SNAPSHOT" with command "cmd-cuc-merge-snapshot"
    Then the merge snapshot Task completes with exact attributed Candidate evidence
    And merge snapshot "MS-CUC-MERGE-SNAPSHOT" remains available as not observed before projection
    When merge snapshot "MS-CUC-MERGE-SNAPSHOT" reaches the read side
    Then merge snapshot "MS-CUC-MERGE-SNAPSHOT" is available without a freshness gate

  Scenario: A qualifying combined-test report verifies one exact snapshot while the view converges
    Given Candidate coordination "MERGE-VERIFY" gives agent "agent-a" an active lease on "lib/merge_verify.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-VERIFY" with command "cmd-cuc-merge-verify-candidate" at head "b" without build context
    Then the Candidate Task completes with an attributed unverified checkpoint
    When the agent registers merge snapshot "MS-CUC-MERGE-VERIFY" with command "cmd-cuc-merge-verify-snapshot"
    Then the merge snapshot Task completes with exact attributed Candidate evidence
    When merge snapshot "MS-CUC-MERGE-VERIFY" reaches the read side
    And the agent submits "passed" merge verification with command "cmd-cuc-merge-verify-pass"
    Then the merge verification Task completes with status "verified"
    And 1 submitted report and 1 verified fact are durable for the exact snapshot
    And the available merge snapshot still reports "unverified"
    When the submitted merge verification reaches the read side twice
    Then the available merge snapshot reports "unverified" with one attributed report
    When the terminal merge verification reaches the read side twice
    Then the available merge snapshot reports "verified" without a freshness gate

  Scenario: A failed report remains durable and a later qualifying report can recover
    Given Candidate coordination "MERGE-RECOVER" gives agent "agent-a" an active lease on "lib/merge_recover.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-RECOVER" with command "cmd-cuc-merge-recover-candidate" at head "b" without build context
    Then the Candidate Task completes with an attributed unverified checkpoint
    When the agent registers merge snapshot "MS-CUC-MERGE-RECOVER" with command "cmd-cuc-merge-recover-snapshot"
    And the agent submits "failed" merge verification with command "cmd-cuc-merge-recover-failed"
    Then the merge verification Task completes with status "failed"
    When the agent submits "passed" merge verification with command "cmd-cuc-merge-recover-passed"
    Then the merge verification Task completes with status "verified"
    And 2 submitted reports and 1 verified fact are durable for the exact snapshot

  Scenario: A stale snapshot binding is rejected from authoritative events
    Given Candidate coordination "MERGE-STALE" gives agent "agent-a" an active lease on "lib/merge_stale.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-STALE" with command "cmd-cuc-merge-stale-candidate" at head "b" without build context
    Then the Candidate Task completes with an attributed unverified checkpoint
    When the agent registers merge snapshot "MS-CUC-MERGE-STALE" with command "cmd-cuc-merge-stale-snapshot"
    And the agent submits merge verification with a stale digest as command "cmd-cuc-merge-stale-verification"
    Then the merge verification Task reports "merge_snapshot_verification_binding_stale" without verification facts
