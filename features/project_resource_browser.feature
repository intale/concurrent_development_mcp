Feature: Inspect project resources and active leases
  The read-only browser presents the latest available projection without becoming lease authority.

  Rule: Ownership comes only from projected lease facts

    @UI-GWT-04
    Scenario: Two running agents do not both appear as resource owners
      Given projected resource rows contain two running agents but only one active lease
      When the browser queries the projected project resources
      Then only the agent with the active lease is presented as the owner

  Rule: Lease lifecycle evidence remains singular and bounded

    @UI-GWT-05
    Scenario: Expanded and renewed memberships remain singular while a released set is inactive
      Given projected resource rows represent expanded renewed and released lease lifecycles after redelivery
      When the browser queries the projected project resources
      Then every active membership is presented once and the released set is absent

    @UI-GWT-06
    Scenario: An old active lease remains visible beside more than one hundred terminal Attempts
      Given projected resource rows retain an old active lease and one hundred one newer terminal Attempts
      When the browser queries the projected project resources
      Then the old active lease remains addressable in the browser
