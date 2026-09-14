@ui-browser @javascript
Feature: Navigate the read-only coordination workspace in a real browser
  A person can discover projected coordination facts, move between focused routes,
  and retain useful available content without knowing opaque identifiers in advance.

  Rule: Project discovery preserves context across paging, errors, navigation, and narrow screens

    @UI-GWT-19
    Scenario: A person discovers and resumes one Project from the catalog
      Given twenty one projected Projects are available for browser discovery
      When the person pages and filters the live Project catalog
      Then a real cursor failure is bounded and Back restores the prior Project page
      And the selected Project opens without exposing its opaque route identity
      And browser Back and refresh preserve the selected Project context
      And the Project remains operable at 390 and 320 pixels

  Rule: Project sections expose focused collection and detail journeys

    @UI-GWT-20
    Scenario: Coordination collections lead to ChangeSet WorkItem and dependency details
      Given representative projected coordination facts share one Project
      When the person follows the live Coordination routes
      Then each coordination detail is focused and independently refreshable

    @UI-GWT-21
    Scenario: Resource inventory and active work intentions lead to separate details
      Given projected resource rows represent expanded renewed withdrawn and expired work-intention lifecycles
      When the person follows the live Resource routes
      Then Resource and work-intention details retain predictable Back routes

    @UI-GWT-22
    Scenario: Current Skills assets Artifacts and relationships remain spatially connected
      Given projected knowledge rows contain current and obsolete revisions of one Skill
      And projected knowledge rows contain related parent and child artifacts with a superseded edge
      When the person follows the live Knowledge routes
      Then current Skill and Artifact relationship details are independently addressable

    @UI-GWT-23
    Scenario: Governance facts retain focused collection and detail routes
      Given representative projected Governance facts share one Project
      When the person follows the live Governance routes
      Then Decision Guidance AgentChoice and impact details stay inside the Project

    @UI-GWT-24
    Scenario: Delivery checkpoints and evidence retain focused collection and detail routes
      Given projected delivery details contain multiple supporting facts
      When the person follows the live Delivery routes
      Then Candidate obligation merge and ReleaseSet details stay independently addressable

  Rule: Global audit and operation facts remain outside every Project

    @UI-GWT-25
    Scenario: Long receipt identities and operation batches remain readable and navigable
      Given projected global audit and operation facts are available
      When the person follows the live global routes
      Then the long command identity does not collide with its tool or status
      And receipt and batch details have predictable Back routes
