Feature: Scoped AI Skill repository
  Agents persist reusable instructions and passive assets through durable MCP Tasks.
  Exact user-chosen scopes separate otherwise equal Skill names, while available views may lag.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Name and scope together identify a Skill

    Scenario: The same Skill name is independently available in home and work scopes
      When the agent publishes Skill "review" in scopes "home" and "work"
      Then both scoped Skill Tasks complete at revision 1 with different Skill IDs
      When both scoped Skill facts reach the read side
      Then listing Skill "review" exposes both exact scopes
      And each scoped Skill returns its own instructions

  Rule: Available Skill views never gate on projection freshness

    Scenario: An older revision stays available while a newer publication is projecting
      Given Skill "deploy" in scope "project:alpha" has projected revision 1
      When the agent publishes revision 2 without projecting it
      Then Skill "deploy" remains available at projected revision 1
      When the agent attempts another publication from stale revision 1
      Then the stale Skill Task completes with revision conflict and a rejected command lifecycle
      When Skill revision 2 reaches the read side
      Then Skill "deploy" is available at revision 2 without a freshness field

  Rule: Assets are passive content tied to one complete revision

    @AUD-SKILL-SNAPSHOT-01
    Scenario: The latest Skill snapshot replaces an obsolete revision
      Given Skill "review-history" in scope "project:alpha" has projected revisions 1 and 2 with different assets
      When the agent retrieves the latest Skill "review-history" and follows its asset manifest
      Then the Skill metadata, manifest, and asset content all describe revision 2
      And retrieving Skill "review-history" without a revision returns revision 2

    @AUD-SKILL-CONCURRENT-PUBLISH-03 @live-subscriptions @concurrency
    Scenario: Concurrent first publications converge on one Skill revision
      Given two independent MCP agents will publish Skill "shared-review" in scope "project:alpha"
      When both agents submit expected revision 0 and reach the Skill decision boundary
      Then both Skill publications have deterministic contention evidence
      When the Skill decision boundary is released
      Then one Skill Task publishes revision 1 and the other completes with revision conflict
      When the winning Skill fact reaches the read side through live subscriptions
      Then Skill "shared-review" exposes exactly the winning revision 1 snapshot

    @AUD-SKILL-PROJECTION-REPLAY-04
    Scenario: The read side converges on the latest Skill revision
      Given Skill "replayed-skill" in scope "project:alpha" has published revisions 1 and 2
      When both published Skill revisions reach the read side
      Then retrieving Skill "replayed-skill" without a revision returns revision 2
      And the obsolete Skill revision is not retrievable

    Scenario: A script asset round-trips through publication and retrieval
      When the agent publishes Skill "release-check" with script asset "scripts/check.sh"
      And the Skill publication reaches the read side
      Then the Skill publication contains granular revision and asset facts
      And the exact script asset content and digest are available through MCP
      And the Skill view exposes the asset manifest without embedding its content

    @CONTENT-SEMANTIC-02 @event-contract
    Scenario: Unicode text and binary assets retain distinct semantic representations under replay
      When the agent publishes and replays Skill "semantic-assets" with Unicode text and binary assets
      And the semantic Skill fact reaches the read side
      Then the Unicode asset is returned as exact text without Base64
      And the binary asset is returned as exact Base64 without text
      And replay leaves one semantic Skill publication fact

    @CONTENT-INVALID-03
    Scenario: Invalid or mixed asset encodings are rejected before Task allocation
      When the agent submits a Skill asset with an invalid mixed encoding representation
      Then the invalid Skill request allocates no Task or command fact
