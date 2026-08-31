Feature: Inspect current project coordination
  The read-only dashboard presents the latest available projected facts without becoming command authority.

  Rule: Scheduled work is presented from exact WorkItem and Attempt facts

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

  Rule: Dependencies remain explicit and eventual consistency remains available

    @UI-GWT-07
    Scenario: An unmet dependency is visible as a blocker
      Given projected dashboard rows contain an unmet work-item dependency
      When the browser queries the projected coordination dashboard
      Then the dashboard identifies the blocking producer and consumer

    @UI-GWT-12 @stale-view
    Scenario: A prior scheduled-work view remains available before a projection catches up
      Given a dashboard work item is ready in the latest projected rows
      When a newer acquisition has not reached the projected rows
      Then the dashboard remains available with the ready state
      When the projected dashboard rows catch up
      Then the dashboard presents the work item as running
