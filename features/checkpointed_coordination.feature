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

  Rule: Overlapping write sets are reserved atomically

    Scenario: Two active agents request an overlapping file through concurrent Tasks
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE"
      When both agents concurrently reserve initial write sets overlapping on "db/schema.rb"
      Then one reservation Task succeeds and the other completes busy
      And the winner owns its complete write set
      And the loser owns no partial write set
      When the winning Attempt reservation reaches the read side
      Then available context exposes the observed lease evidence without a freshness claim

  Rule: An agent expands its current write set without renewing it

    Scenario: Added file evidence reaches an available read model after the durable Task
      Given agent "agent-a" has reserved "app/a.rb" for active Attempt "A-CUC-EXPAND" in ChangeSet "CS-CUC-EXPAND"
      When the agent expands the current write set with "app/b.rb"
      Then the expansion Task succeeds without extending the lease deadline
      And the previous context remains available before expansion projection
      When the write-set expansion reaches the read side
      Then available context exposes both observed files without a freshness claim

  Rule: An agent renews its complete observed lease set

    Scenario: A durable renewal extends ownership while an older context remains available
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for renewable Attempt "A-CUC-RENEW" in ChangeSet "CS-CUC-RENEW"
      When the agent renews the complete observed lease set
      Then the renewal Task succeeds without changing lease identities or fencing tokens
      And the previous context remains available before renewal projection
      When the write-set renewal reaches the read side
      Then available context exposes the later observed deadline without a freshness claim

  Rule: An agent releases its complete observed lease set

    Scenario: A durable release frees the set while an older context remains available
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for releasable Attempt "A-CUC-RELEASE" in ChangeSet "CS-CUC-RELEASE"
      When the agent releases the complete observed lease set
      Then the release Task succeeds without changing lease identities or fencing tokens
      And the previous context remains available before release projection
      When the write-set release reaches the read side
      Then available context exposes the observed release without a freshness claim

  Rule: Elapsed lease availability does not wait for expiry audit

    Scenario: A successor reserves an elapsed file before the predecessor timer runs
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-EXPIRY"
      When agent "agent-a" reserves "app/shared.rb" for 30 seconds at "2026-08-22T10:00:00Z"
      And that reservation reaches the available read side
      And after its deadline agent "agent-b" reserves the same file before the expiry policy runs
      Then the successor reservation Task succeeds with the next fencing token
      And the successor was admitted without an expiry audit fact
      When the expired predecessor timer is handled
      Then the timer is superseded and cannot affect the successor
      And the predecessor's older context remains available without a freshness claim

  Rule: Deliberately submitted guidance remains attributed evidence until a later decision

    Scenario: Direct guidance becomes available without activating policy
      When agent "host-1" records direct guidance "Do not use Redis in billing." as message "M-CUC-GDN-1" in conversation "C-CUC-GDN-1"
      Then the guidance Task records one evidence-only fact
      And the available guidance query honestly reports that message as not observed
      When the guidance reaches the read side
      Then the available guidance preserves its text and unauthenticated attribution without a freshness claim

    Scenario: A globally reused forwarded message identity is denied
      When agent "host-1" forwards guidance "Keep tests on RSpec." as message "M-CUC-GDN-2" in conversation "C-CUC-GDN-2"
      And agent "host-2" tries to record the same message in conversation "C-CUC-GDN-OTHER"
      Then the second guidance Task completes with message identity denial
      And only the first Conversation owns the forwarded evidence
