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
    And the migration does not copy its own maintenance facts into restored history

  Scenario: An agent transfers only complete post-cutoff development memory into an accepted target
    Given an MCP agent supports checkpointed Tasks
    And frozen historical repository and Task evidence exists
    When the agent starts a history migration through MCP
    And the agent records and updates an Artifact after the accepted history cutoff
    And the agent requests the closed development-memory suffix through MCP
    And the migrated repository and command receipts are replayed
    Then the agent retrieves the current and original observed Artifact content through MCP
    And the accepted base history is unchanged and maintenance history is excluded
