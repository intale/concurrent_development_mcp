@wip @knowledge-repository
Feature: Scoped Skills and connected Development Artifacts
  Agents retrieve the latest available knowledge projection while authoritative changes remain
  cohesive facts in UUIDv7 entity streams.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Skill scope is part of natural identity

    Scenario: The same Skill name is independent in two scopes
      When an agent publishes Skill "review" in scopes "home" and "project:alpha"
      Then exact name and scope lookup returns two different UUIDv7 Skill identities
      And changing one Skill revision does not change the other
      And global Skill listing can filter by exact name and project scope

    Scenario: A Skill revision relates immutable assets without dumping them into publication
      Given a Skill revision includes text and executable binary assets
      When the agent publishes the revision through MCP
      Then each asset has its own UUIDv7 stream and cohesive path, content, and executability facts
      And relation facts assign the assets to the revision
      And the SkillRevisionPublished fact contains only the revision identity

  Rule: Development Artifacts remain mutable, connected knowledge

    Scenario: Content and source changes preserve one Artifact identity
      Given a Development Artifact was allocated for an exact scope and source locator
      When an agent changes its source revision and text content through MCP
      Then both changes retain the same UUIDv7 Artifact stream
      And separate source and content facts preserve the history
      And content representation descriptors exist only in typed metadata

    Scenario: A clean agent walks parent and child Artifact links from projections
      Given a README Artifact references two child documentation Artifacts
      When the relationships have reached the read side
      Then outgoing traversal from the README discovers both children
      And incoming traversal from either child discovers its parent
      And each result offers a public action to fetch the related projected content
      And an unresolved external URL remains a URL-only Artifact reference

  Rule: Knowledge collections expose stable latest-state navigation

    Scenario Outline: A collection is ordered by its latest contributing event
      Given projected <records> were updated by events with distinct created_at values
      When an agent lists <records> through MCP
      Then results sort by updated_at descending and stable identity ascending
      And cursor pagination uses the same pair
      And no projection revision slice or freshness gate is exposed

      Examples:
        | records               |
        | Skills                |
        | Development Artifacts |
        | ChangeSets            |
        | WorkItems             |
        | Work Intentions       |
