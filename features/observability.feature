@observability @live-subscriptions
Feature: Observe coordination without changing its behavior
  Agents still receive the same asynchronous Tasks and eventual read models.
  Telemetry distinguishes acceptance, technical delivery and business outcomes
  without publishing instructions, identities or command payloads.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Scenario: Accepted work completes through the real subscription pipeline
    When the agent submits a private Skill while the workers are stopped
    Then telemetry reports acceptance while the Task remains working
    When the real subscription workers process the observed Task
    Then the Skill is available unchanged through the MCP read side
    And telemetry records all three subscription sets and their Rails SQL
    And finished telemetry has bounded dimensions and no private payloads

  Scenario: Business conflict is not a subscription crash
    Given the observed Skill has already been published
    When the agent submits the observed Skill with a stale revision
    Then the Task returns the original revision conflict through MCP
    And telemetry separates the conflict from successful handler delivery
    And finished telemetry has bounded dimensions and no private payloads

  Scenario: Cancellation remains a public Task operation
    When the agent submits a private Skill while the workers are stopped
    And the agent cancels the observed Task through MCP
    Then the original cancellation acknowledgement and status are preserved
    And telemetry reports cancellation without publishing the Task identity
    And finished telemetry has bounded dimensions and no private payloads
