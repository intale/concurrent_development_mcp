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
