@terminal_build_progress
Feature: Available terminal build progress
  Agents finish immutable checkpoints through durable MCP Tasks.
  The write side protects coordination rules while the available context converges independently.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A final Candidate closes its WorkItem and eventually its ChangeSet

    Scenario: Final Candidate completion remains available through projection lag and converges
      Given terminal Candidate coordination "SINGLE" is ready for agent "agent-terminal"
      When the agent submits the final terminal Candidate and releases its write set
      Then available context exposes that exact Candidate without inventing a completion command
      When the agent completes the WorkItem through an MCP Task
      Then the terminal Task records one selected Candidate, completed Attempt, and completed WorkItem
      And the older acquired context remains available before terminal projection
      When terminal facts and build progress reach the read side
      Then available context exposes the completed WorkItem, Attempt, and ChangeSet without a freshness gate

    Scenario: Final completion survives repeated interrupted Attempts
      Given terminal Candidate coordination "RECOVERED" is ready for agent "agent-terminal"
      When the terminal agent is interrupted 2 times and reacquires the WorkItem through MCP Tasks
      And the agent submits the final terminal Candidate and releases its write set
      And the agent completes the WorkItem through an MCP Task
      Then the terminal Task records one selected Candidate, completed Attempt, and completed WorkItem
      And the recovered WorkItem preserves each interruption before its terminal facts

  Rule: Dependency progress converges through the production Sagas and read subscription

    Scenario: Completion unlocks a dependent WorkItem without withholding an older view
      Given terminal coordination "DEPENDENCY" has a consumer blocked on producer completion
      When the producer completes through an MCP Task and build progress handles its completion
      Then the consumer's older blocked context remains available
      When downstream readiness reaches the read side
      Then available context exposes the exact ready consumer without inventing an acquisition command
      And the satisfied dependency retains its declaration identity and exact producer completion evidence
