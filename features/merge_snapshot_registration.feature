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

  Scenario: Exact verified evidence grants authorization while its available view catches up
    Given Candidate coordination "MERGE-AUTH-GRANT" gives agent "agent-a" an active lease on "lib/merge_auth_grant.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-AUTH-GRANT" with command "cmd-cuc-merge-auth-grant-candidate" at head "b" without build context
    And the agent registers merge snapshot "MS-CUC-MERGE-AUTH-GRANT" with command "cmd-cuc-merge-auth-grant-snapshot"
    And merge snapshot "MS-CUC-MERGE-AUTH-GRANT" reaches the read side
    And the agent submits "passed" merge verification with command "cmd-cuc-merge-auth-grant-verification"
    Then the merge verification Task completes with status "verified"
    When the agent requests merge authorization with command "cmd-cuc-merge-auth-grant"
    Then the merge authorization Task completes with durable outcome "granted"
    And the available merge snapshot has no observed authorization yet
    When the merge authorization reaches the read side twice
    Then the available merge snapshot reports authorization "granted" without a freshness gate

  Scenario: A changed target base is a durable authorization denial, not a Task failure
    Given Candidate coordination "MERGE-AUTH-STALE" gives agent "agent-a" an active lease on "lib/merge_auth_stale.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-AUTH-STALE" with command "cmd-cuc-merge-auth-stale-candidate" at head "b" without build context
    And the agent registers merge snapshot "MS-CUC-MERGE-AUTH-STALE" with command "cmd-cuc-merge-auth-stale-snapshot"
    And merge snapshot "MS-CUC-MERGE-AUTH-STALE" reaches the read side
    And the agent submits "passed" merge verification with command "cmd-cuc-merge-auth-stale-verification"
    Then the merge verification Task completes with status "verified"
    When the agent requests merge authorization against a changed target base with command "cmd-cuc-merge-auth-stale"
    Then the merge authorization Task completes with durable outcome "denied"
    And the authorization explains "target_base_binding_stale"

  Scenario: An exact open merge-gate obligation blocks authorization from authoritative facts
    Given Rails 4 to Rails 5 Candidate pair "MERGE-AUTH-OPEN" has registered attributed impact surfaces
    When the user activates "merge_gate" Candidate impact policy through guidance Tasks
    And the policy reaction is delivered twice
    Then one exact open Rails obligation is durable under "merge_gate"
    When the integrator registers exact Rails pair snapshot "MS-CUC-MERGE-AUTH-OPEN"
    And the agent submits "passed" merge verification with command "cmd-cuc-merge-auth-open-verification"
    Then the merge verification Task completes with status "verified"
    When the agent requests merge authorization with command "cmd-cuc-merge-auth-open"
    Then the merge authorization Task completes with durable outcome "denied"
    And the authorization explains "required_obligation_open"

  Scenario: An exact current grant permits one attributed external merge observation
    Given Candidate coordination "MERGE-OBSERVED" gives agent "agent-a" an active lease on "lib/merge_observed.rb"
    When the agent submits Candidate "CAN-CUC-MERGE-OBSERVED" with command "cmd-cuc-merge-observed-candidate" at head "b" without build context
    And the agent registers merge snapshot "MS-CUC-MERGE-OBSERVED" with command "cmd-cuc-merge-observed-snapshot"
    And merge snapshot "MS-CUC-MERGE-OBSERVED" reaches the read side
    And the agent submits "passed" merge verification with command "cmd-cuc-merge-observed-verification"
    And the agent requests merge authorization with command "cmd-cuc-merge-observed-authorization"
    Then the merge authorization Task completes with durable outcome "granted"
    When the agent records the exact external merge with command "cmd-cuc-merge-observed"
    Then the merge observation Task completes with attributed unverified evidence
    And the available merge snapshot has no observed merge yet
    When the merge observation reaches the read side twice
    Then the available merge snapshot reports the exact merge without a freshness gate
