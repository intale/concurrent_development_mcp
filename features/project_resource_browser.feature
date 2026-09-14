Feature: Inspect project resources and active work intentions
  The read-only browser presents the latest available projection without becoming write authority.

  Rule: Ownership comes only from projected work-intention facts

    @UI-GWT-04
    Scenario: Two running agents do not both appear as resource owners
      Given projected resource rows contain two running agents but only one active work intention
      When the browser queries the projected active Resource work intentions
      Then only the agent with the active work intention is presented as an owner

  Rule: Work-intention lifecycle evidence remains singular and historically addressable

    @UI-GWT-05
    Scenario: Active memberships stay singular while expired history remains available
      Given projected resource rows represent expanded renewed withdrawn and expired work-intention lifecycles
      When the browser queries active work intentions and the expired intention detail
      Then every active membership is presented once while withdrawn and expired intentions are absent
      And the expired work-intention detail remains addressable as historical evidence

    @UI-GWT-06
    Scenario: An old active work intention remains visible beside more than one hundred terminal Attempts
      Given projected resource rows retain an old active work intention and one hundred one newer terminal Attempts
      When the browser queries the projected active Resource work intentions
      Then the old active work intention remains addressable in the browser
