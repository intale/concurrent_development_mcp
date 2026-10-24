@event-contract
Feature: Focused MCP usage Skills
  Clients load relevant instructions on demand rather than receiving a full manual at discovery.
  Product guides use the ordinary event-sourced Skill repository.

  @USAGE-01 @live-subscriptions
  Scenario: A fresh installation supplies discoverable scoped guides through real Tasks
    Given a project Skill has the same name as the product entry guide
    When the operator installs the bundled product usage Skills
    Then discovery routes a new client to the product getting-started Skill
    And the client can retrieve every bundled guide through skill_get
    And the project Skill is unchanged

  @USAGE-02 @live-subscriptions
  Scenario: Reinstalling an unchanged bundle is an authoritative publication no-op
    Given the product usage Skills are installed
    When the operator installs the bundled product usage Skills again
    Then every publication reports the existing revision without replacing a Skill

  @USAGE-03 @live-subscriptions
  Scenario: An updated bundle publishes a new immutable Skill revision
    Given the product usage Skills are installed
    When the operator publishes an updated knowledge-management guide
    Then the client retrieves the updated guide without retaining superseded read revisions
    And the other product guide revisions are unchanged
    When the operator installs the bundled product usage Skills again
    Then the updater restores its bundled snapshot as the next revision

  @USAGE-05
  Scenario: An interrupted installation retains a resumable durable Task
    Given no usage Skill Task workers are running
    When the product installer times out on its first pending publication
    And the unchanged run is resumed while workers are still stopped
    Then it reports the same working Task without cancelling it
    When the usage Skill workers start
    Then the original publication eventually becomes a retrievable Skill

  @USAGE-04 @stale-view
  Scenario: Stale Skill context cannot force an installer overwrite
    Given an authoritative product guide exists without its read projection
    When the installer exhausts its bounded revision-conflict attempts
    Then it reports the conflict without replacing the authoritative guide
