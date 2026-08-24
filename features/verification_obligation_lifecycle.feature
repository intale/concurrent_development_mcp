@verification_obligation_lifecycle
Feature: Verification obligation lifecycle coordination
  Users can waive exact current obligations, while policy changes asynchronously invalidate stale obligations.
  Available views remain useful during projection lag and never claim freshness.

  Background:
    Given an MCP agent supports checkpointed Tasks
    And an open Rails verification obligation "LIFECYCLE"
    And the obligation creation is available on the read side

  Scenario: A user waives one exact obligation through a checkpointed Task
    When user "user-label" submits waiver command "cmd-cuc-obligation-waiver"
    Then the waiver Task is durable before any waiver fact
    When the waiver Task executes
    Then the waiver Task completes with an attributed coordination override
    And the available obligation still reports open before waiver projection
    When the obligation lifecycle reaches the read side twice
    Then the available obligation reports waived with the exact attributed reason

  Scenario: A corrected Candidate policy invalidates the old obligation through a Saga
    When the user corrects the Candidate impact policy through guidance Tasks
    And the validity policy reaction is delivered twice
    Then one policy invalidation is durable with exact Saga tracing
    And the available obligation still reports open before invalidation projection
    When the obligation lifecycle reaches the read side twice
    Then the available obligation reports invalidated by the exact later partition
