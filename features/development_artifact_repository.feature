Feature: Development Artifact repository
  Agents preserve bounded development evidence through durable MCP Tasks.
  Projected metadata remains available independently from passive content retrieval.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A clean agent discovers migration from MCP without a prescribed project layout

    Scenario: Endpoint instructions and schemas teach semantic client-side import
      When a clean agent asks the MCP endpoint how to migrate development memory
      Then the endpoint assigns project discovery to the agent without assuming paths or runtimes
      And the import-capable schemas require exact content and caller-owned provenance

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

  Rule: Linked documentation is a directed graph that a clean agent can walk both ways

    @linked-artifacts @stale-view
    Scenario: A clean agent walks from a README to two children and back from a shared child
      Given a README, two linked documents, and another parent are captured and mapped
      And the caller declares README links with parent-segment and fragment evidence
      And the other parent contains the shared API document
      When the linked Artifact facts reach the read side
      And the clean agent walks outgoing relationships from the README
      Then it discovers both exact child Artifacts and fetches their passive content
      When the clean agent walks incoming relationships from the shared API document
      Then it sees both exact parents with mixed relationship kinds and peer summaries
      And the README edge preserves its literal parent-segment, fragment, and normalized locator

    @linked-artifacts @stale-view @AUD-ART-LOCATOR-ACTION-01 @AUD-ART-LOCATOR-PAGE-02
    Scenario: Locator resolution reports lag and immutable revision ambiguity without choosing latest
      Given two immutable revisions at one exact locator are captured but not projected
      When the clean agent resolves that locator before projection
      Then the locator is absent with a bounded projection-lag retry action
      When both locator revisions reach the read side
      Then the locator is ambiguous and offers both exact revisions without choosing latest
      When the clean agent follows one exact revision action
      Then exactly that immutable Artifact and its content action are returned
      And an unknown exact locator remains honestly absent

  Rule: Replay and convergence cannot hide or duplicate graph edges

    @linked-artifacts @event-contract
    Scenario: Exact relationship replay produces one durable and projected edge
      Given a captured parent and child are available for relationship replay
      When the same relationship command is executed through two Tasks
      And its relation fact reaches the read side twice
      Then both Tasks expose one logical relation result
      And one relation fact, command receipt, and projected edge exist

    @linked-artifacts @stale-view
    Scenario: A late older declaration is found beyond the previous observation window
      Given an earlier-captured parent has two committed relationships but only the later declaration is projected
      When the clean agent reads one outgoing relationship page
      Then the available page contains the later declaration and a completed observation window
      When the older declaration reaches the read side after that cursor
      And the clean agent resumes from the returned relationship cursor
      Then the older declaration is returned despite its earlier event position

    @linked-artifacts @stale-view @AUD-ART-RELATION-SUPERSESSION-01 @AUD-ART-RELATION-REPLAY-02
    Scenario: A completed relationship cursor observes a later supersession exactly once
      Given a projected Artifact relationship and an unprojected replacement are available
      When the clean agent completes the initial relationship observation window
      And the supersession reaches the read side before its replacement declaration
      Then resuming the completed cursor exposes the original relationship as superseded
      When the supersession is replayed and its older replacement declaration arrives
      Then the next cursor exposes the active replacement once without regressing the original edge
