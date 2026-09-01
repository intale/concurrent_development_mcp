Feature: Browse the latest available project catalog
  A user can discover an exact Project scope and inspect its projected Repositories.
  The latest available response remains useful while newer projections become available.

  Rule: Exact Project scope is preserved across the browser and GraphQL boundary

    @UI-GWT-01
    Scenario: The browser lists only Projects matching the selected exact scope
      Given exact project scope "project:test/ui-catalog-a" has projected repository "ui-catalog-a"
      And exact project scope "project:test/ui-catalog-b" has projected repository "ui-catalog-b"
      When the browser queries the project catalog for "project:test/ui-catalog-a"
      Then the project catalog contains only repository "ui-catalog-a"
      And Rails serves the standalone project browser shell
      And every project browser route serves the same standalone shell
      And the browser-facing GraphQL schema exposes Query without Mutation or Subscription

  Rule: An available Project page remains readable while projections advance

    @UI-GWT-10 @stale-view
    Scenario: The browser keeps a prior Project page while a newer Repository projection appears
      Given exact project scope "project:test/ui-catalog-stale" has projected repository "ui-catalog-current"
      When the browser reads that project before repository "ui-catalog-new" is projected
      Then the project catalog remains available with repository "ui-catalog-current"
      And the unprojected repository "ui-catalog-new" is not presented as current
      When repository "ui-catalog-new" becomes available in that Project projection
      Then the project catalog contains repositories "ui-catalog-current" and "ui-catalog-new"
