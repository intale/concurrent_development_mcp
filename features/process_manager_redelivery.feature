@wip @saga @redelivery
Feature: Idempotent process-manager decisions
  A process manager persists each downstream command decision before dispatch and remains correct
  across crashes, duplicate delivery, and subscription restarts.

  Background:
    Given an MCP command has emitted a source event for a Saga

  Rule: A persisted process step is the idempotency marker

    Scenario: Redelivery after planning but before dispatch uses the original identities
      Given the process manager persisted a ProcessStepPlanned fact for the source event
      And it stopped before dispatching the target command
      When the source event is delivered again
      Then the manager finds the same process step by its readable natural selector
      And it dispatches the persisted command and child UUIDv7 identities verbatim
      And exactly one downstream business decision is recorded

    Scenario: Redelivery after target commit but before checkpoint creates no duplicate fact
      Given the planned target command committed its facts
      And the subscription stopped before advancing its checkpoint
      When the source event is delivered again
      Then the manager replays the exact persisted command
      And the command receipt returns the already committed outcome
      And the subscription advances only after every required process step is terminal

  Rule: Saga tracing expresses cause and shared purpose

    Scenario: A multi-step Saga preserves native event tracing
      When the process manager plans and dispatches two downstream steps
      Then every event in the chain has the source event native correlation_id
      And each follow-up event caused_by references its immediate persisted parent
      And correlation_id is read from the Event reader rather than copied into metadata

    Scenario: A process manager never manufactures another aggregate event
      When the process manager reacts to its source event
      Then its only decision output is a command
      And that command rebuilds Given state from bounded pg_eventstore reads
      And neither the process manager nor command consults a Rails projection
      And no private subscription lifecycle operation is invoked

