Feature: Development Artifact repository
  Agents preserve bounded development evidence through durable MCP Tasks.
  Projected metadata remains available independently from passive content retrieval.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Evidence is classified, attributed, and retrieved without executing content

    Scenario: Documentation and web-search evidence are discoverable through exact filters
      When the agent captures documentation and web-search Development Artifacts
      Then both Artifact Tasks complete with different immutable IDs
      When the Development Artifact facts reach the read side
      Then listing the shared evidence labels returns both Artifacts
      And Artifact metadata excludes content bytes
      And focused Artifact content returns the exact documentation text as passive data

  Rule: Changed bytes are new facts connected by explicit relationships

    Scenario: A changed binary profile supersedes its earlier capture
      When the agent captures two binary profile versions from one source
      Then the changed profile has a different immutable Artifact ID
      When the agent declares that the changed profile supersedes the earlier profile
      And the binary Artifact facts reach the read side
      Then the changed profile exposes the supersession relationship
      And its exact Base64 content is available but never executed
