Feature: Inspect checkpointed delivery and global operation batches
  The read-only browser presents latest delivery projections without becoming write authority.

  Rule: Project attribution comes only from persisted coordination relationships

    @UI-GWT-16
    Scenario: Candidates, obligations, merge snapshots, and ReleaseSets stay within the exact project
      Given projected delivery rows contain exact and unrelated project facts
      When the browser queries the projected project delivery
      Then only delivery facts with persisted relationships to the exact project are presented

  Rule: Delivery detail remains semantic and typed

    @UI-GWT-17
    Scenario: Verification evidence and merge authorization decisions are navigable
      Given projected delivery rows contain verification evidence and merge authorization history
      When the browser queries the related delivery details
      Then typed evidence and authorization facts are presented without normalized support rows

  Rule: Operation batches remain global

    @UI-GWT-18
    Scenario: Batch outcomes are not attributed from command arguments
      Given projected operation batches contain commands mentioning separate projects
      When the browser queries global operation batches
      Then typed batch outcomes are presented without inferred project ownership or raw arguments
