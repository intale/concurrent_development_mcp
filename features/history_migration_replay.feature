@history-migration @live-subscriptions
Feature: Migrated history remains usable through the public read side
  Historical evidence is transformed into current facts before cutover.
  Migration provenance must not replace command ownership or actor attribution.

  Scenario: An agent discovers a restored repository after a real migration and replay
    Given an MCP agent supports checkpointed Tasks
    And frozen historical repository and Task evidence exists
    When the agent starts a history migration through MCP
    And the migrated repository and command receipts are replayed
    Then the agent discovers the restored repository through MCP
    And the restored receipt refers to facts owned by its original logical command
