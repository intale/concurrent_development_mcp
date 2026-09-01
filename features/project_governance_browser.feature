Feature: Inspect project governance and global command receipts
  The read-only browser presents latest available coordination policy facts without becoming command authority.

  Rule: Decision membership uses complete projected coordination history

    @UI-GWT-13
    Scenario: An Attempt-scoped Decision remains visible after the bounded context window advances
      Given projected governance rows retain an old Attempt Decision outside the bounded context window
      When the browser queries the projected project governance
      Then the old Decision is presented with Attempt membership provenance

  Rule: Related governance facts remain typed and project isolated

    @UI-GWT-14
    Scenario: Guidance interpretations and AgentChoice impacts stay within the exact project
      Given projected governance rows contain related and unrelated guidance choices and impacts
      When the browser queries the projected project governance and related details
      Then only typed governance facts associated with the exact project are presented

  Rule: Command receipts are global audit facts

    @UI-GWT-15
    Scenario: Command receipts are not attributed to the project in the browser
      Given projected governance rows contain command receipts from separate coordination contexts
      When the browser queries global command receipts from the project governance route
      Then both receipts are presented as typed global audit facts without intermediate command content
