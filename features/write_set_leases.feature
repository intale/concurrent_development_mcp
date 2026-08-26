@event-contract
Feature: Dynamic write-set leases
  Agents reserve complete normalized resource sets through authoritative Tasks.
  Available projections report observations without authorizing edits.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Overlapping write sets are reserved atomically

    @CDM-LEASE-001 @concurrency @stale-view
    Scenario: Two active agents request an overlapping file through concurrent Tasks
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE"
      When both agents concurrently reserve initial write sets overlapping on "db/schema.rb"
      Then one reservation Task succeeds and the other completes busy
      And the winner owns its complete write set
      And the loser owns no partial write set
      When the winning Attempt reservation reaches the read side
      Then available context exposes the observed lease evidence without a freshness claim

    @CDM-LEASE-002 @concurrency
    Scenario: Disjoint complete write sets do not contend
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE-DISJOINT"
      When both agents concurrently reserve their disjoint files
      Then both disjoint reservation Tasks succeed with complete write sets

    @CDM-LEASE-003 @concurrency
    Scenario: Alias paths select one normalized consistency boundary
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE-ALIAS"
      When both agents concurrently reserve aliases "db/schema.rb" and "db/tmp/../schema.rb"
      Then one normalized reservation wins and the loser owns no lease

    @CDM-CANCEL-001
    Scenario: Cancelling a queued reservation writes no lease
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE-CANCEL"
      When agent "agent-a" cancels a queued reservation for "app/shared.rb" before execution
      Then the cancelled reservation writes no lease fact
      When agent "agent-b" deliberately reserves "app/shared.rb"
      Then the successor obtains fencing token 1

  Rule: An agent expands its current write set without renewing it

    @CDM-LEASE-007 @stale-view
    Scenario: Added file evidence reaches an available read model after the durable Task
      Given agent "agent-a" has reserved "app/a.rb" for active Attempt "A-CUC-EXPAND" in ChangeSet "CS-CUC-EXPAND"
      When the agent expands the current write set with "app/b.rb"
      Then the expansion Task succeeds without extending the lease deadline
      And the previous context remains available before expansion projection
      When the write-set expansion reaches the read side
      Then available context exposes both observed files without a freshness claim

  Rule: An agent renews its complete observed lease set

    @CDM-LEASE-008 @stale-view
    Scenario: A durable renewal extends ownership while an older context remains available
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for renewable Attempt "A-CUC-RENEW" in ChangeSet "CS-CUC-RENEW"
      When the agent renews the complete observed lease set
      Then the renewal Task succeeds without changing lease identities or fencing tokens
      And the previous context remains available before renewal projection
      When the write-set renewal reaches the read side
      Then available context exposes the later observed deadline without a freshness claim

    @CDM-LEASE-006
    Scenario: Renewal makes an older observed expiry non-authoritative
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-RENEW-BUSY"
      And agent "agent-a" reserves "app/shared.rb" for 30 seconds at "2026-08-22T10:00:00Z"
      When the predecessor renews its exact lease set before the old deadline
      Then the authoritative deadline moves beyond the old expiry
      When agent "agent-b" deliberately reserves after the old deadline but before the renewed deadline
      Then the contender remains busy with the renewed deadline

  Rule: An agent releases its complete observed lease set

    @CDM-LEASE-010 @stale-view
    Scenario: A durable release frees the set while an older context remains available
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for releasable Attempt "A-CUC-RELEASE" in ChangeSet "CS-CUC-RELEASE"
      When the agent releases the complete observed lease set
      Then the release Task succeeds without changing lease identities or fencing tokens
      And the previous context remains available before release projection
      When the write-set release reaches the read side
      Then available context exposes the observed release without a freshness claim

    @CDM-LEASE-004
    Scenario: Exact release replay returns one logical lifecycle
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for releasable Attempt "A-CUC-RELEASE-REPLAY" in ChangeSet "CS-CUC-RELEASE-REPLAY"
      When the agent releases the complete observed lease set
      Then the release Task succeeds without changing lease identities or fencing tokens
      When the exact release command is retried through another Task
      Then both release Task handles expose one logical result

    @CDM-LEASE-005 @stale-view
    Scenario: A deliberate reservation succeeds after authoritative release
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-RELEASE-TAKEOVER"
      And agent "agent-a" reserves "app/shared.rb" for 300 seconds at "2026-08-22T10:00:00Z"
      When the predecessor releases its exact lease set
      Then the authoritative release succeeds
      When agent "agent-b" deliberately reserves after the release
      Then the successor obtains fencing token 2

  Rule: Interrupted work is abandoned without disturbing successor ownership

    @CDM-ATTEMPT-001 @event-contract
    Scenario: An agent abandons current work and reacquires it through a fresh Attempt
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for releasable Attempt "A-CUC-ABANDON" in ChangeSet "CS-CUC-ABANDON"
      When the agent abandons the Attempt because its execution was interrupted
      Then the abandonment Task releases current fences and requeues the WorkItem
      When the exact abandonment command is retried through another Task
      Then both abandonment Task handles expose one logical result
      When the agent reacquires the requeued WorkItem as fresh Attempt "A-CUC-ABANDON-NEXT"
      Then the fresh Attempt starts from a new base declaration while the old Attempt remains terminal

    @CDM-ATTEMPT-002 @concurrency
    Scenario: Abandonment never releases a fence acquired by a successor
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-ABANDON-SUPERSEDED"
      And agent "agent-a" reserves "app/shared.rb" for 30 seconds at "2026-08-22T10:00:00Z"
      And after its deadline agent "agent-b" reserves the same file before the expiry policy runs
      When the expired predecessor abandons its Attempt
      Then the abandonment requeues the predecessor and leaves the successor fence untouched

    @CDM-ATTEMPT-003 @event-contract
    Scenario: A Candidate checkpoint prevents Attempt abandonment
      Given agent "agent-a" has attached Candidate "CAN-CUC-ABANDON" to active Attempt "A-CUC-CAN-ABANDON"
      When the agent tries to abandon the Candidate-bearing Attempt
      Then abandonment is denied without releasing leases or requeueing the WorkItem

  Rule: Elapsed lease availability does not wait for expiry audit

    @CDM-LEASE-009 @stale-view
    Scenario: A successor reserves an elapsed file before the predecessor timer runs
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-EXPIRY"
      When agent "agent-a" reserves "app/shared.rb" for 30 seconds at "2026-08-22T10:00:00Z"
      And that reservation reaches the available read side
      And after its deadline agent "agent-b" reserves the same file before the expiry policy runs
      Then the successor reservation Task succeeds with the next fencing token
      And the successor was admitted without an expiry audit fact
      When the expired predecessor timer is handled
      Then the timer is superseded and cannot affect the successor
      When the expired predecessor tries to renew its old fence
      Then the predecessor renewal is denied without affecting the successor
      When the expired predecessor tries to release its old fence
      Then the predecessor release is denied without affecting the successor
      And the predecessor's older context remains available without a freshness claim
