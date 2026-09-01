Feature: Inspect project governance
  The read-only browser presents latest available coordination policy facts without becoming command authority.

  Rule: Decision membership uses complete projected coordination history

    @UI-GWT-13
    Scenario: An Attempt-scoped Decision remains visible after the bounded context window advances
      Given projected governance rows retain an old Attempt Decision outside the bounded context window
      When the browser opens the focused Decision collection and detail
      Then the old Decision is presented with Attempt membership provenance

  Rule: Governance is scoped to every Repository member of one exact Project

    @UI-GWT-14
    Scenario: Related Guidance AgentChoices and impacts have dedicated project-bound details
      Given projected governance rows span two Project members and an unrelated Project
      When the browser opens each focused Governance collection and detail
      Then only typed Governance facts associated with the exact Project are presented

  Rule: One collection failure does not suppress another available projection

    @UI-GWT-15
    Scenario: A malformed Decision cursor leaves projected Guidance available
      Given projected Governance rows contain available Guidance
      When one Governance collection receives a malformed cursor
      Then the failing collection is isolated and the available Guidance is returned
