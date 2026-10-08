@candidate
Feature: Attributed Candidate checkpoints
  Agents submit immutable repository checkpoints through durable Tasks.
  Authoritative work-intention and head ownership decisions remain independent of available projections.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A valid Candidate is one traced authoritative checkpoint with independently available evidence

    Scenario: A successful checkpoint becomes available through the production read subscription
      Given Candidate coordination "SUCCESS" gives agent "agent-a" an active work intention on "lib/candidate.rb"
      When the agent submits Candidate "CAN-CUC-SUCCESS" with command "cmd-cuc-can-success" at head "b" and build context
      Then the Candidate Task completes with an attributed unverified checkpoint
      And Candidate "CAN-CUC-SUCCESS" has one traced atomic checkpoint with manifest and build context
      And Candidate "CAN-CUC-SUCCESS" is honestly not observed before projection
      When the Candidate "CAN-CUC-SUCCESS" evidence and Attempt context reach the read side
      Then available Candidate "CAN-CUC-SUCCESS" preserves evidence and Attempt context without a freshness claim

    Scenario: Exact command replay returns the original checkpoint without duplicate facts
      Given Candidate coordination "REPLAY" gives agent "agent-a" an active work intention on "lib/replay.rb"
      When the agent submits Candidate "CAN-CUC-REPLAY" with command "cmd-cuc-can-replay" at head "b" without build context
      And the exact Candidate command is retried through its original Task
      Then the replayed Candidate Task exposes the same result
      And Candidate "CAN-CUC-REPLAY" has one submission, manifest, head registration, and successful command lifecycle

  Rule: Invalid observations never create partial Candidate authority

    Scenario: Stale fencing evidence completes its durable Task as a conflict
      Given Candidate coordination "STALE" gives agent "agent-a" an active work intention on "lib/stale.rb"
      When the agent submits Candidate "CAN-CUC-STALE" with stale fencing evidence
      Then the Candidate Task completes with conflict "work_intention_observations_mismatch"
      And denied Candidate "CAN-CUC-STALE" writes no target facts

    Scenario: Malformed evidence is rejected before Task allocation
      Given Candidate coordination "INVALID" gives agent "agent-a" an active work intention on "lib/invalid.rb"
      When the agent attempts Candidate "CAN-CUC-INVALID" without work-intention observations
      Then the Candidate request is rejected before Task allocation
      And invalid Candidate "CAN-CUC-INVALID" writes no target facts

    @CDM-BOUND-001 @event-contract
    Scenario: Candidate file evidence is bounded independently of directory work intentions
      Given Candidate coordination "BOUND" gives agent "agent-a" an active work intention on "lib/bound.rb"
      When the agent attempts Candidate "CAN-CUC-BOUND" with 1001 changed files
      Then the Candidate request is rejected and its schema directs the agent to split WorkItems
      And invalid Candidate "CAN-CUC-BOUND" writes no target facts

  Rule: Available history may lag while the write side protects head ownership

    Scenario: An older checkpoint remains available while a newer Candidate is still projecting
      Given Candidate coordination "LAG" gives agent "agent-a" an active work intention on "lib/lag.rb"
      When Candidate "CAN-CUC-LAG-OLD" at head "b" is submitted and fully projected
      And newer Candidate "CAN-CUC-LAG-NEW" at head "e" commits without projection
      Then the prior Candidate history and Attempt checkpoint remain available while the newer Candidate is unobserved
      When the Candidate "CAN-CUC-LAG-NEW" evidence and Attempt context reach the read side
      Then Candidate history includes both checkpoints and Attempt context points to "CAN-CUC-LAG-NEW" without a freshness claim

    Scenario: Concurrent Candidates for one repository head have one complete owner
      Given Candidate coordinations "RACE-A" and "RACE-B" give two agents independent work intentions
      When both agents concurrently submit Candidates for the same repository head
      Then one Candidate Task succeeds and the other reports a registered-head conflict
      And the head-conflict receipt resolves exactly to the winning ownership fact
      And the winning Candidate owns one complete checkpoint while the loser owns no target facts
