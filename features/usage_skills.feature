Feature: Static server capability Skills
  Agents discover and load server usage instructions without installation or publication.
  Project Skills remain independently managed knowledge entities.

  Scenario: A clean agent discovers the complete capability catalog before any domain setup
    Given the built-in server usage Skills are available
    When the client lists server Skills without a scope
    Then every public function belongs to one discoverable capability guide
    And discovery routes a new client to the product getting-started Skill
    And the client can retrieve every built-in guide immediately

  Scenario: A client pages and filters the static catalog
    When the client pages through server Skills two at a time
    Then every built-in guide appears once in deterministic name order
    And an exact server Skill name filter selects one guide

  Scenario: Missing built-in content never falls through to stored knowledge
    When the client requests unknown built-in content and a different bundle revision
    Then each request returns a typed static not-found outcome

  @event-contract @live-subscriptions
  Scenario: A project Skill sharing a built-in name remains an ordinary separate entity
    Given a project Skill has the same name as the product entry guide
    When the client lists server Skills without a scope
    Then the project Skill is unchanged
    And the client can retrieve every built-in guide immediately
