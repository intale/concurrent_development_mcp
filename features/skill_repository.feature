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
      Then the stale Skill Task completes with revision conflict and no command fact
      When Skill revision 2 reaches the read side
      Then Skill "deploy" is available at revision 2 without a freshness field

  Rule: Assets are passive content tied to one complete revision

    Scenario: A script asset round-trips through publication and retrieval
      When the agent publishes Skill "release-check" with script asset "scripts/check.sh"
      And the Skill publication reaches the read side
      Then the exact script asset content and digest are available through MCP
      And the Skill view exposes the asset manifest without embedding its content
