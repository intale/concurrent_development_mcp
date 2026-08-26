@event-contract
Feature: Durable MCP Task protocol
  Agents coordinate concurrent repository work through durable Tasks.
  The write side remains authoritative while available read models may lag.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Retrying a lost request cannot duplicate coordination facts

    @CDM-TASK-001 @live-subscriptions
    Scenario: An agent retries a completed ChangeSet command through a new Task
      When agent "planner-1" submits ChangeSet "CS-CUC-RETRY" with command "cmd-cuc-retry"
      Then the Task is durable before coordination begins
      When the current Task completes through live subscriptions
      Then the current Task completes successfully
      When the same command is retried through another live Task
      Then both Task handles expose the same result
      And the command and ChangeSet facts exist only once

    @CDM-TASK-002
    Scenario: Changed input cannot reuse a completed command identity
      When agent "planner-1" submits ChangeSet "CS-CUC-REUSE" with command "cmd-cuc-reuse"
      And the Task executor processes the current Task
      Then the current Task completes successfully
      When the completed command identity is submitted with a changed ChangeSet goal
      And the Task executor processes the current Task
      Then the current Task completes with coordination denial "command_id_reused"
      And only the original command and ChangeSet facts remain

    @CDM-OP-001 @stale-view
    Scenario: A projected command receipt is available without becoming an authorization gate
      When agent "planner-1" submits ChangeSet "CS-CUC-OPERATION" with command "cmd-cuc-operation"
      And the Task executor processes the current Task
      Then the current Task completes successfully
      When the successful command receipt reaches the read side
      Then operation_get exposes the receipt without a freshness claim

  Rule: Domain denials are durable tool outcomes

    @CDM-TASK-003
    Scenario: An agent targets a ChangeSet that does not exist
      When agent "planner-1" submits WorkItem "W-CUC-DENIED" to missing ChangeSet "CS-CUC-MISSING" with command "cmd-cuc-denied"
      And the Task executor processes the current Task
      Then the current Task completes with coordination denial "change_set_not_found"
      And the denied command writes no coordination facts

  Rule: Queued work can be cancelled cooperatively

    @CDM-TASK-004
    Scenario: An agent cancels before execution starts
      When agent "planner-1" submits ChangeSet "CS-CUC-CANCEL" with command "cmd-cuc-cancel"
      And the agent cancels the current Task before execution
      And the Task executor later receives the cancelled Task
      Then the current Task is cancelled
      And the cancelled command writes no coordination facts

  Rule: Read availability does not depend on projection freshness

    @CDM-STALE-002 @stale-view
    Scenario: An agent reads useful context while a newer WorkItem is still projecting
      Given the read side has projected ChangeSet "CS-CUC-STALE"
      When agent "planner-1" completes WorkItem "W-CUC-STALE" with command "cmd-cuc-stale" without projecting it
      Then the agent can still read the previous ChangeSet context
      And the newer WorkItem exists only on the write side of that response

  Rule: The server has no synchronous fallback for clients without Tasks

    @CDM-TASK-005
    Scenario: A client without the Tasks extension attempts a mutation
      Given an MCP client does not support checkpointed Tasks
      When agent "planner-1" attempts ChangeSet "CS-CUC-CAPABILITY" with command "cmd-cuc-capability"
      Then the server requires the Tasks extension
      And the rejected request writes no coordination facts
