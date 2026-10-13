@event-contract @live-subscriptions
Feature: Authoritative and self-explanatory mutation completion
  An agent confirms requested effects through its Task, not through entity read-back.
  Ordinary projections remain available and may lag without changing the Task outcome.

  Background:
    Given an MCP agent supports checkpointed Tasks
    And both read projection sets are stopped

  @TASK-CONTRACT-01 @TASK-CONTRACT-03 @TASK-CONTRACT-04
  Scenario: Successful persistence and replay do not depend on read-side confirmation
    When a clean agent creates a ChangeSet and waits only for its Task
    Then the terminal receipt confirms durable facts and says no read-back is required
    And the entity projection can still report not found without requiring another creation
    When another client replays the exact original request
    Then the original Task returns the identical authoritative outcome
    And the requested ChangeSet facts were produced once without starting a projector

  @TASK-CONTRACT-02
  Scenario: A denial is a completed tool error even with no projected receipt
    When a clean agent creates a ChangeSet and waits only for its Task
    And another agent requests the same ChangeSet using a new command
    Then the denied Task completes with no target effects and no read-back requirement

  @TASK-CONTRACT-05 @TASK-CONTRACT-06
  Scenario: Acceptance is not completion and a mixed Batch retains its success
    When an agent submits a two-item Skill Batch with execution paused
    Then the accepted Batch Task remains working and explains that effects are not confirmed
    When the Batch is released without starting any read projection
    Then its Task reports one success and one rejection as a partial failure
    And the successful publication remains durable without any projected Skill

  @TASK-CONTRACT-07
  Scenario: Cancelling an unstarted Batch needs no projection confirmation
    When an agent submits a two-item Skill Batch with execution paused
    And the agent cancels the paused Batch without reading its projection
    Then the cancellation Task confirms only the durable cancellation request
    When the Batch is released without starting any read projection
    Then the original Batch Task reports cancellation with two not-run items and no target effects
