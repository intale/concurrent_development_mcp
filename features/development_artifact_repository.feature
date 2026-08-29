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

    @CONTENT-TEXT-01 @CONTENT-DERIVE-01
    Scenario: Documentation and web-search evidence are discoverable through exact filters
      When the agent captures documentation and web-search Development Artifacts
      Then both Artifact Tasks complete with different immutable IDs
      When the Development Artifact facts reach the read side
      Then listing the shared evidence labels returns both Artifacts
      And Artifact metadata excludes content bytes
      And focused Artifact content returns the exact documentation text as passive data

    @CONTENT-EXTERNAL-REFERENCE-04 @event-contract
    Scenario: An external reference stores only its URL and never a fetched body
      When the agent captures an external reference to "https://example.test/reference"
      And the external-reference Artifact fact reaches the read side
      Then its persisted and projected content is exactly the URL followed by one newline
      And the external-reference content contains no binary or fetched representation

  Rule: Changed bytes are new facts connected by explicit relationships

    @CONTENT-BINARY-01
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
    Scenario: Exact relationship replay remains one edge after a read-subscription restart
      Given a captured parent and child are available for relationship replay
      When the same relationship command is executed through two Tasks
      And its relation fact reaches the read side after a subscription restart
      Then both Tasks expose one logical relation result
      And one relation fact, command receipt, and projected edge exist

  Rule: Source observations are immutable while classification is explicitly correctable

    @linked-artifacts @AUD-ART-OBSERVATION-01
    Scenario: Identical bytes observed at two Git revisions remain separate historical observations
      When the agent captures identical documentation bytes from two Git revisions
      Then both capture Tasks name one content-addressed Artifact and two observation IDs
      When both Artifact observations reach the read side
      Then exact observation actions retrieve both Git revisions independently
      And both observations lead to the same passive content

    @linked-artifacts @AUD-ART-CLASSIFICATION-02
    Scenario: Classification correction preserves captured bytes and source provenance
      Given one projected documentation observation has an inaccurate title and labels
      When the agent corrects that observation classification through a Task
      Then the correction advances the classification revision without capturing new bytes
      And exact observation retrieval exposes the corrected title and labels
      And its content digest and immutable provenance are unchanged

  Rule: Relationship ontology is canonical, authoritative, and navigable

    @linked-artifacts @AUD-ART-DEAD-LINK-03
    Scenario: Internal targets require authoritative facts while external targets remain unverified
      Given a projected source Artifact is available for target validation
      When the agent declares a relationship to a nonexistent Candidate
      Then the relation Task is denied and no relation fact exists
      When the agent declares a relationship to an external URL
      Then the relation is accepted with an unverified target status

    @linked-artifacts @AUD-ART-GRAPH-DIRECTION-04
    Scenario: Independent agents converge on the canonical direction for one reference
      Given two independent MCP agents know the same projected parent and child Artifacts
      When both agents declare that the parent references the child
      Then both relation Tasks identify one directed edge
      And outgoing parent traversal and incoming child traversal expose inverse directions

    @linked-artifacts @AUD-ART-GRAPH-FOLLOW-05
    Scenario: Every verified internal target exposes a usable public follow-up action
      Given a source Artifact and authoritative coordination targets are available
      When the agent declares one documented relationship to each internal target kind
      And the internal-target relationships reach the read side
      Then every relationship supplies an action accepted by its public MCP tool

  Rule: Graph capacity is bounded and supersession releases active capacity

    @linked-artifacts @AUD-ART-GRAPH-CAPACITY-06
    Scenario: Active and lifetime graph limits are explicit before history can grow without bound
      Given a source Artifact has reached its active relationship capacity
      When the agent supersedes one active relationship
      Then active graph capacity remains available for one replacement edge
      And Artifact metadata reports active and lifetime capacity separately
      When another declaration would exceed the lifetime graph limit
      Then it is denied from bounded history with the discoverable lifetime limit
