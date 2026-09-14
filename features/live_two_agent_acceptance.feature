@live-subscriptions
Feature: Live two-agent checkpointed coordination
  Two independent coding agents use only serialized MCP exchanges to coordinate concurrent work,
  tolerate an available but stale read model, and reconstruct the finished project without local memory.

  @AUD-TWO-LUNA-JOURNEY-01 @concurrency
  Scenario: Two 5.6-luna agents checkpoint and release one concurrent multi-repository change
    Given project scope "project:acceptance/two-luna-live" has an active ChangeSet for two independent 5.6-luna agents
    When both agents discover the ChangeSet from scope and acquire their WorkItems through MCP
    And their exclusive parent and shared child work-intention requests reach the real decision boundary concurrently
    Then agent A declares the exclusive parent while agent B receives the blocker context
    And agent B can declare a disjoint intention while agent A remains active
    When both agents persist final Candidate checkpoints through MCP
    And an available stale context is used for a command after its intention set has been withdrawn
    Then the stale context remains available and the authoritative command is rejected
    When the agents persist the project Decision and reusable Skill through MCP
    And an external verifier merges, verifies, and activates the ReleaseSet through MCP
    Then the live ReleaseSet Saga completes the ChangeSet
    When a replacement client knows only the project scope and follows public MCP results
    Then it reconstructs Attempts, checkpoints, Decisions, Skills, Artifacts, and the release
