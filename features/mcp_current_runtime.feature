Feature: Current coordination runtime after history-transfer retirement
  Agents keep importing ordinary development memory through MCP.
  One-off database transfer is not a supported product operation.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Scenario: A clean agent discovers product imports without a history-transfer endpoint
    When a clean agent asks the MCP endpoint how to migrate development memory
    Then the endpoint assigns project discovery to the agent without assuming paths or runtimes
    And the import-capable schemas require exact content and caller-owned provenance
    And no history-transfer tool or instruction is advertised

  Scenario: Rejected database transfer does not prevent normal documentation capture
    When the agent requests the retired database-transfer tool
    Then the request is rejected before a command or Task is recorded
    When the agent captures documentation and web-search Development Artifacts
    Then both Artifact Tasks complete with different stable UUIDv7 IDs
    When the Development Artifact facts reach the read side
    Then listing the shared evidence labels returns both Artifacts
    And Artifact metadata excludes content bytes
    And focused Artifact content returns the exact documentation text as passive data
