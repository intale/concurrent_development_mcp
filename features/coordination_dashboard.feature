Feature: Inspect current project coordination
  The read-only dashboard presents the latest available projected facts without becoming command authority.

  Rule: Scheduled work is presented from exact WorkItem and Attempt facts

    @UI-GWT-26
    Scenario: ChangeSets are filtered by their exact lifecycle status
      Given projected dashboard rows contain planning, active, and completed ChangeSets
      When the browser filters projected ChangeSets by status "completed"
      Then only the completed ChangeSet is presented

    @UI-GWT-02
    Scenario: A project presents pending, ready, and running scheduled work
      Given projected dashboard rows contain pending, ready, and running scheduled work
      When the browser queries the projected coordination dashboard
      Then the dashboard presents the exact scheduled work states

    @UI-GWT-03
    Scenario: Two 5.6-luna agents work concurrently in one project
      Given projected dashboard rows contain agents "luna-one" and "luna-two" on distinct running work
      When the browser queries the projected coordination dashboard
      Then both running agents retain their distinct Attempt attribution

    Scenario: A selected WorkItem keeps its Attempt and checkpoint in one focused detail
      Given projected dashboard rows contain a running WorkItem with a Candidate checkpoint
      When the browser opens the projected WorkItem detail
      Then the WorkItem detail presents its exact Attempt and checkpoint attribution

  Rule: Dependencies remain explicit and eventual consistency remains available

    @UI-GWT-07
    Scenario: An unmet dependency is visible as a blocker
      Given projected dashboard rows contain an unmet work-item dependency
      When the browser queries the projected coordination dashboard
      Then the dashboard identifies the blocking producer and consumer

    @UI-GWT-11
    Scenario: Scheduled work from another project does not cross the exact project boundary
      Given projected dashboard rows contain scheduled work for the selected and an unrelated project
      When the browser queries the projected coordination dashboard
      Then only the selected project's scheduled work is presented

    @UI-GWT-12 @stale-view
    Scenario: A prior scheduled-work view remains available before a projection catches up
      Given a dashboard work item is ready in the latest projected rows
      When a newer acquisition has not reached the projected rows
      Then the dashboard remains available with the ready state
      When the projected dashboard rows catch up
      Then the dashboard presents the work item as running
