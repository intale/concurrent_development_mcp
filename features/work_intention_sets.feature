@event-contract
Feature: Dynamic work intentions
  Agents declare shared or exclusive intentions for normalized resources through authoritative Tasks.
  Intentions communicate planned work; only an exclusive intention prevents overlapping declarations.
  Available projections report observations without authorizing edits.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Exclusive work intentions reject overlapping declarations atomically

    @AUD-LEASE-DF-CONFLICT-01 @LEASE-DESC-01 @live-subscriptions @concurrency
    Scenario: An exclusive directory intention blocks a later shared child-file intention
      Given two independent MCP agents have live active Attempts in ChangeSet "CS-AUD-LSE-DIR-FIRST"
      When agent "agent-a" declares an exclusive intention for directory "app/models" through a public Task
      And agent "agent-b" declares a shared intention for file "app/models/user.rb" through a public Task
      Then the first hierarchical intention succeeds and the second completes busy with its blocker context
      And only the directory resource has a durable intention declaration

    @AUD-LEASE-DF-CONFLICT-02 @LEASE-DESC-01 @live-subscriptions @concurrency
    Scenario: A shared child-file intention blocks a later exclusive parent-directory intention
      Given two independent MCP agents have live active Attempts in ChangeSet "CS-AUD-LSE-FILE-FIRST"
      When agent "agent-a" declares a shared intention for file "app/models/user.rb" through a public Task
      And agent "agent-b" declares an exclusive intention for directory "app/models" through a public Task
      Then the first hierarchical intention succeeds and the second completes busy with its blocker context
      And only the file resource has a durable intention declaration

    @LEASE-EQUAL-01 @live-subscriptions
    Scenario: A second agent cannot introduce another kind at a registered path
      Given two independent MCP agents have live active Attempts in ChangeSet "CS-ID-LSE-EQUAL-PATH"
      When agent "agent-a" declares a shared intention for file "app/models" through a public Task
      And agent "agent-b" tries to resolve directory "app/models" for leasing
      Then the first hierarchical reservation succeeds and the alternative kind is denied
      And only the current file resource has a durable intention declaration

    @LEASE-FILE-PREFIX-01 @live-subscriptions
    Scenario: Shared file intentions coexist at descendant-looking paths
      Given two independent MCP agents have live active Attempts in ChangeSet "CS-ID-LSE-FILE-PREFIX"
      When agent "agent-a" declares a shared intention for file "app/models" through a public Task
      And agent "agent-b" declares a shared intention for file "app/models/user.rb" through a public Task
      Then both hierarchical reservation Tasks complete successfully

    @AUD-LEASE-DISJOINT-03 @live-subscriptions @concurrency
    Scenario: Disjoint directory and file resources remain independently leasable
      Given two independent MCP agents have live active Attempts in ChangeSet "CS-AUD-LSE-DISJOINT"
      When both agents submit public reservation Tasks for disjoint resources and reach the reservation decision boundary
      Then both reservation operations have deterministic contention evidence
      When the reservation decision boundary is released
      Then both hierarchical reservation Tasks complete successfully

    @AUD-LEASE-PATH-BYTES-04 @live-subscriptions
    Scenario: A literal backslash is rejected instead of aliased to a Git path separator
      Given two independent MCP agents have live active Attempts in ChangeSet "CS-AUD-LSE-PATH-BYTES"
      When agent "agent-a" submits literal resource path "app\\models\\user.rb" through public MCP
      Then MCP rejects the unsupported path before allocating a Task
      And no work intention is stored for either path spelling

    @CDM-LEASE-001 @concurrency @stale-view
    Scenario: Concurrent shared and exclusive declarations for one file produce one blocker
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE"
      When both agents concurrently declare initial work intentions overlapping on "db/schema.rb"
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

    @CDM-CANCEL-001
    Scenario: Cancelling a queued reservation writes no lease
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-LSE-CANCEL"
      When agent "agent-a" cancels a queued reservation for "app/shared.rb" before execution
      Then the cancelled reservation writes no work-intention fact
      When agent "agent-b" deliberately reserves "app/shared.rb"
      Then the successor obtains fencing token 1

  Rule: An agent expands its current intention set without renewing it

    @CDM-LEASE-007 @stale-view
    Scenario: Added file evidence reaches an available read model after the durable Task
      Given agent "agent-a" has reserved "app/a.rb" for active Attempt "A-CUC-EXPAND" in ChangeSet "CS-CUC-EXPAND"
      When the agent expands the current write set with "app/b.rb"
      Then the expansion Task succeeds without extending the lease deadline
      And the previous context remains available before expansion projection
      When the write-set expansion reaches the read side
      Then available context exposes both observed files without a freshness claim

  Rule: An agent renews its complete observed intention set

    @CDM-LEASE-008 @stale-view
    Scenario: A durable renewal extends ownership while an older context remains available
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for renewable Attempt "A-CUC-RENEW" in ChangeSet "CS-CUC-RENEW"
      When the agent renews the complete observed lease set
      Then the renewal Task succeeds without changing lease identities or fencing tokens
      And the previous context remains available before renewal projection
      When the write-set renewal reaches the read side
      Then available context exposes the later observed deadline without a freshness claim

    @INTENTION-RENEWAL-HISTORY-01 @stale-view
    Scenario: A second renewal projects the immediately previous deadline
      Given agent "agent-a" has reserved "app/a.rb" and "app/b.rb" for renewable Attempt "A-CUC-RENEW-TWICE" in ChangeSet "CS-CUC-RENEW-TWICE"
      When the agent renews the complete observed lease set
      Then the renewal Task succeeds without changing lease identities or fencing tokens
      When the write-set renewal reaches the read side
      Then available context exposes the later observed deadline without a freshness claim
      When the agent renews the same intention set again
      Then the renewal Task succeeds without changing lease identities or fencing tokens
      When the write-set renewal reaches the read side
      Then available context exposes the later observed deadline without a freshness claim

  Rule: An agent withdraws its complete observed intention set

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
      When the exact release command is submitted again
      Then both release responses expose the original Task and one logical result

    @CDM-LEASE-005 @stale-view
    Scenario: A deliberate reservation succeeds after authoritative release
      Given agents "agent-a" and "agent-b" have active Attempts in ChangeSet "CS-CUC-RELEASE-TAKEOVER"
      And agent "agent-a" reserves "app/shared.rb" for 300 seconds
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
      When the exact abandonment command is submitted again
      Then both abandonment responses expose the original Task and one logical result
      When the agent reacquires the requeued WorkItem as fresh Attempt "A-CUC-ABANDON-NEXT"
      Then the fresh Attempt starts from a new base declaration while the old Attempt remains terminal

    @CDM-ATTEMPT-003 @event-contract
    Scenario: A final Candidate prevents Attempt abandonment
      Given agent "agent-a" has submitted "final" Candidate "CAN-CUC-ABANDON" for active Attempt "A-CUC-CAN-ABANDON"
      When the agent tries to abandon the Candidate-bearing Attempt
      Then abandonment is denied without releasing leases or requeueing the WorkItem

    @CDM-ATTEMPT-004 @event-contract
    Scenario: An intermediate Candidate remains as history when its Attempt is abandoned
      Given agent "agent-a" has submitted "intermediate" Candidate "CAN-CUC-ABANDON" for active Attempt "A-CUC-CAN-ABANDON"
      When the agent tries to abandon the Candidate-bearing Attempt
      Then the checkpoint remains recorded while the Attempt is abandoned and requeued
