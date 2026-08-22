Feature: Checkpointed cooperative coordination
  Agents coordinate concurrent repository work through durable Tasks.
  The write side remains authoritative while available read models may lag.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Retrying a lost request cannot duplicate coordination facts

    Scenario: An agent retries a completed ChangeSet command through a new Task
      When agent "planner-1" submits ChangeSet "CS-CUC-RETRY" with command "cmd-cuc-retry"
      Then the Task is durable before coordination begins
      When the Task executor processes the current Task
      Then the current Task completes successfully
      When the same command is retried and processed through another Task
      Then both Task handles expose the same result
      And the command and ChangeSet facts exist only once

  Rule: Domain denials are durable tool outcomes

    Scenario: An agent targets a ChangeSet that does not exist
      When agent "planner-1" submits WorkItem "W-CUC-DENIED" to missing ChangeSet "CS-CUC-MISSING" with command "cmd-cuc-denied"
      And the Task executor processes the current Task
      Then the current Task completes with coordination denial "change_set_not_found"
      And the denied command writes no coordination facts

  Rule: Queued work can be cancelled cooperatively

    Scenario: An agent cancels before execution starts
      When agent "planner-1" submits ChangeSet "CS-CUC-CANCEL" with command "cmd-cuc-cancel"
      And the agent cancels the current Task before execution
      And the Task executor later receives the cancelled Task
      Then the current Task is cancelled
      And the cancelled command writes no coordination facts

  Rule: Read availability does not depend on projection freshness

    Scenario: An agent reads useful context while a newer WorkItem is still projecting
      Given the read side has projected ChangeSet "CS-CUC-STALE"
      When agent "planner-1" completes WorkItem "W-CUC-STALE" with command "cmd-cuc-stale" without projecting it
      Then the agent can still read the previous ChangeSet context
      And the newer WorkItem exists only on the write side of that response

  Rule: The server has no synchronous fallback for clients without Tasks

    Scenario: A client without the Tasks extension attempts a mutation
      Given an MCP client does not support checkpointed Tasks
      When agent "planner-1" attempts ChangeSet "CS-CUC-CAPABILITY" with command "cmd-cuc-capability"
      Then the server requires the Tasks extension
      And the rejected request writes no coordination facts
