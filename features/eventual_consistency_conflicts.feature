@wip @eventual-consistency
Feature: Available projections and authoritative write conflicts
  Read models remain useful while delayed, and commands protect invariants using only bounded
  pg_eventstore state.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Projection lag never disables reads

    Scenario: An agent reads an older project view while projection is delayed
      Given a coordination fact is durable and its read projection has not processed it
      When the agent requests the project view through MCP
      Then MCP returns the latest available projection without a pending or freshness error
      And the response does not claim that the projection authorizes a write

    Scenario: Projection chronology is deterministic under redelivery
      Given two source streams update one projected row in opposite delivery order
      When the projector handles both events and then redelivers either event
      Then the row updated_at equals the greatest contributing Event created_at
      And the projected state does not regress
      And each source event is claimed idempotently by projection name and version

  Rule: Stale commands fail at the write boundary

    Scenario: A stale single-stream decision reports an optimistic conflict
      Given two agents read the same authoritative stream revision
      When the first command changes that lifecycle and the second writes from the old revision
      Then the second Task fails with stale_stream
      And its error explains that refreshing and retrying may succeed
      And the coordinator does not retry the wrong expected revision internally

    Scenario: A stale independent-property decision reports a DCB conflict
      Given two agents read the same title type-and-marker revision for one Artifact
      When the first command changes that title and the second writes from the old selector revision
      Then the second Task fails with stale_selector
      And its error names the exact event types and readable marker
      And unrelated Artifact property events do not cause that conflict

    Scenario: A cross-stream decision exhausts only internal transaction-race retries
      Given a Client multiple decision encounters repeated serialization or deadlock races
      When its bounded internal retry limit is exhausted
      Then the Task fails with concurrent_transaction_exhausted
      And the response says an explicit client retry may succeed

