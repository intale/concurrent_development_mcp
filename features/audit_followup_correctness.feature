Feature: Audited coordination remains correct under replay, interruption, and concurrency
  The coordinator must expose durable MCP Task outcomes and available read views
  without allowing public clients, stale projections, or accumulated history to
  violate authoritative event-sourced coordination rules.

  Rule: Every modeled domain denial becomes a terminal tool result

    @AUD2-TASK-DENIAL-TERMINAL-01 @live-subscriptions
    Scenario Outline: A modeled denial completes its originating MCP Task
      Given the production subscription sets are running
      And no <target> with identifier <identifier> exists
      When agent "audit-agent" submits the <tool> command through public MCP
      Then the returned MCP Task eventually completes with isError true
      And its error is valid for the originating <tool> output schema
      And redelivery leaves one terminal Task outcome

      Examples:
        | target      | identifier                                 | tool                   |
        | Batch       | 018f22e2-7b8d-7dd4-9f8a-65a70fc02111   | operation_batch_cancel |
        | ReleaseSet  | RS-AUD2-MISSING                           | release_verification_record |

  Rule: Coordination context converges after work is abandoned

    @AUD2-CONTEXT-ABANDON-01 @live-subscriptions
    Scenario: An abandoned Attempt requeues its WorkItem in available context
      Given agent "agent-a" owns an active Attempt for WorkItem "W-AUD2-ABANDON"
      When agent "agent-a" abandons that Attempt through public MCP
      Then the abandonment Task completes successfully
      And the latest available WorkItem context eventually reports it ready
      And the abandoned Attempt remains attributed in its history

    @AUD2-CONTEXT-REACQUIRE-02 @live-subscriptions
    Scenario: A replacement agent resumes a requeued WorkItem from MCP context
      Given agent "agent-a" abandoned its active Attempt for WorkItem "W-AUD2-REACQUIRE"
      When independent agent "agent-b" reconstructs context and acquires the WorkItem
      Then agent "agent-b" receives a new authorized Attempt
      And the context identifies only that Attempt as active

    @AUD2-CONTEXT-ATTEMPT-WINDOW-03 @live-subscriptions
    Scenario: Lifetime Attempt churn cannot halt coordination projection
      Given WorkItem "W-AUD2-WINDOW" has more than 100 completed or abandoned Attempts
      When another agent acquires a fresh Attempt through public MCP
      Then the latest available context eventually includes the fresh Attempt
      And the recent Attempt window remains bounded
      And older Attempt history remains discoverable through bounded pages

  Rule: Process-manager identities and tracing cannot be preempted

    @wip @AUD2-SAGA-ID-PREEMPT-BATCH-01 @live-subscriptions
    Scenario: A public client cannot occupy a future Batch process command identity
      Given an accepted Operation Batch whose next process command identity is known
      When an agent submits that internal command identity through a public mutation
      Then MCP rejects the input before allocating a Task
      And the live Batch Saga eventually completes normally

    @wip @AUD2-SAGA-ID-PREEMPT-RELEASE-02 @live-subscriptions
    Scenario: A public client cannot occupy a future ReleaseSet process command identity
      Given a ReleaseSet whose next lifecycle command identity is known
      When an agent submits that internal command identity through a public mutation
      Then MCP rejects the input before allocating a Task
      And the live ReleaseSet Saga eventually reaches its valid terminal outcome

    @wip @AUD2-BATCH-CORRELATION-03 @live-subscriptions
    Scenario: A Batch replay of an unrelated prior command retains one Batch trace
      Given a target command completed before an Operation Batch under another correlation
      When a live Batch processes an item containing the exact prior command
      Then the item has one successful outcome
      And every event in the Batch Saga has the Batch correlation identifier
      And duplicate source delivery produces no additional logical outcome

  Rule: Resource-boundary history remains bounded without becoming unavailable

    @wip @AUD2-LEASE-HISTORY-ROLLOVER-01 @live-subscriptions
    Scenario: A released hot resource remains leasable after lifecycle rollover
      Given a file boundary has exceeded the former lifecycle-history limit
      And every prior lease on that boundary is released or expired
      When an agent reserves the file through public MCP
      Then the reservation Task completes successfully
      And its authoritative decision uses a bounded snapshot plus delta

    @wip @AUD2-LEASE-ROLLOVER-RACE-02 @live-subscriptions @concurrency
    Scenario: Rollover racing a conflicting reservation preserves one valid lease decision
      Given two independent agents can reach the same resource-boundary decision concurrently
      When the rollover command and conflicting reservation reach the deterministic database barrier
      And the barrier releases both operations
      Then both operations terminate without a partial write
      And the resulting boundary has at most one active overlapping lease
      And every retry retains its logical event identities

  Rule: Clean clients share canonical repository and public-action semantics

    @wip @AUD2-REPOSITORY-BOOTSTRAP-RACE-01 @live-subscriptions @concurrency
    Scenario: Two clean agents concurrently register one logical repository key
      Given independent agents "agent-a" and "agent-b" know only the same project scope and repository key
      When both registrations reach the deterministic database barrier with different proposed UUIDs
      And the barrier releases both registrations
      Then one canonical Repository UUID is authoritative for that scope and key
      And both agents discover the same canonical Repository through MCP
      And leases under either client use the shared Repository namespace

    @wip @AUD2-NEXT-ACTION-EXECUTABLE-02
    Scenario: Every advertised next action is an executable MCP request
      Given an MCP result contains one or more next actions
      When an agent validates each action against current tool discovery
      Then every action is complete and schema-valid for its target tool
      And no mutation action contains placeholders or omitted required intent

    @wip @AUD2-ACTOR-ATTRIBUTION-03
    Scenario: MCP describes actor labels as attribution rather than authentication
      Given an agent inspects current MCP discovery
      When the agent reads a mutation actor schema and description
      Then the contract does not claim that a supplied actor label proves identity
      And no authentication or session capability is implied
