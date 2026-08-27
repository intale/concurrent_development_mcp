@verification_obligation_claim
Feature: Agents claim verification obligations through checkpointed Tasks
  A claim gives one agent temporary exclusive coordination with a monotonic fence.
  It remains an attributed coordination fact, not proof that verification work started or succeeded.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A successful claim is durable, traced, fenced, and replayable

    Scenario: A first claim completes through a Task and exact replay returns its receipt
      Given an open Rails verification obligation "CLAIM-FIRST"
      When agent "agent-blue" submits claim command "cmd-cuc-claim-first" for 300 seconds
      Then a checkpointed Task exists before any claim fact
      When the claim Task executes
      Then the claim Task completes for "agent-blue" with fencing token 1
      And the durable claim carries exact Task tracing
      And the claim result describes coordination without claiming work or verification
      When the same claim command is submitted as another Task
      And the claim Task executes
      Then replay returns the original claim without another claim fact

  Rule: Active ownership and concurrent races grant only one token

    Scenario: An active claim denies another agent without a target command receipt
      Given an open Rails verification obligation "CLAIM-ACTIVE"
      When agent "agent-blue" submits claim command "cmd-cuc-claim-active-blue" for 300 seconds
      And the claim Task executes
      Then the claim Task completes for "agent-blue" with fencing token 1
      When agent "agent-green" submits claim command "cmd-cuc-claim-active-green" for 300 seconds
      And the claim Task executes while the first claim is active
      Then the claim Task reports the active "agent-blue" claim as a conflict
      And the denied command has no receipt or claim fact

    Scenario: Two concurrent Task executions produce one token-one winner
      Given an open Rails verification obligation "CLAIM-RACE"
      When agents "agent-blue" and "agent-green" claim concurrently
      Then exactly one Task wins token 1 and the other reports an active-claim conflict

  Rule: Expiry permits a new monotonic fence without rewriting history

    Scenario: An expired claim receives token two
      Given an open Rails verification obligation "CLAIM-EXPIRY"
      When agent "agent-blue" submits claim command "cmd-cuc-claim-expiry-blue" for 30 seconds
      And the claim Task executes
      Then the claim Task completes for "agent-blue" with fencing token 1
      When the active claim expires
      And agent "agent-green" submits claim command "cmd-cuc-claim-expiry-green" for 300 seconds
      And the claim Task executes
      Then the claim Task completes for "agent-green" with fencing token 2
      And both immutable claim facts retain their distinct fences

  Rule: Available reads may lag and later converge

    Scenario: A committed claim remains available as stale content before projection converges
      Given an open Rails verification obligation "CLAIM-VIEW"
      And the obligation creation is available on the read side
      When agent "agent-blue" submits claim command "cmd-cuc-claim-view" for 300 seconds
      And the claim Task executes
      Then the claim Task completes for "agent-blue" with fencing token 1
      And the available view still reports an open unclaimed obligation
      When the claim reaches the read side twice
      Then the available view reports the open active claim
