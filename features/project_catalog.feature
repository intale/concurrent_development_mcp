@live-subscriptions
Feature: Browse the latest available project catalog
  A user can select an exact project scope and inspect its projected repositories.
  Projection lag never makes an already available catalog unavailable.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Exact project scope is preserved across the browser and GraphQL boundary

    @UI-GWT-01
    Scenario: The browser lists only projects in the selected exact scope
      Given exact project scope "project:test/ui-catalog-a" has registered repository "ui-catalog-a"
      And exact project scope "project:test/ui-catalog-b" has registered repository "ui-catalog-b"
      When the browser queries the project catalog for "project:test/ui-catalog-a"
      Then the project catalog contains only repository "ui-catalog-a"
      And Rails serves the standalone project browser shell
      And the browser-facing GraphQL schema exposes Query without Mutation or Subscription

  Rule: An available project page remains readable while projection delivery catches up

    @UI-GWT-10 @stale-view
    Scenario: The browser receives the prior project page while a newer registration awaits projection
      Given exact project scope "project:test/ui-catalog-stale" has registered repository "ui-catalog-current"
      When project-catalog projection delivery pauses and repository "ui-catalog-new" registers in that scope
      Then the project catalog remains available with repository "ui-catalog-current"
      And the unprojected repository "ui-catalog-new" is not presented as current
      When project-catalog projection delivery restarts
      Then the project catalog eventually contains repositories "ui-catalog-current" and "ui-catalog-new"
