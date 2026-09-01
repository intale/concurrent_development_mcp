Feature: Inspect project resources and active leases
  The read-only browser presents the latest available projection without becoming lease authority.

  Rule: Ownership comes only from projected lease facts

    @UI-GWT-04
    Scenario: Two running agents do not both appear as resource owners
      Given projected resource rows contain two running agents but only one active lease
      When the browser queries the projected active Resource leases
      Then only the agent with the active lease is presented as the owner

  Rule: Lease lifecycle evidence remains singular and historically addressable

    @UI-GWT-05
    Scenario: Active memberships stay singular while expired history remains available
      Given projected resource rows represent expanded renewed released and expired lease lifecycles
      When the browser queries active leases and the expired lease detail
      Then every active membership is presented once while released and expired leases are absent
      And the expired lease detail remains addressable as historical evidence

    @UI-GWT-06
    Scenario: An old active lease remains visible beside more than one hundred terminal Attempts
      Given projected resource rows retain an old active lease and one hundred one newer terminal Attempts
      When the browser queries the projected active Resource leases
      Then the old active lease remains addressable in the browser
