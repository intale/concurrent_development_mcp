Feature: Inspect focused checkpointed delivery views
  The read-only browser exposes independent Project collections and details without becoming write authority.

  Rule: Project attribution comes only from persisted coordination relationships

    @UI-GWT-16
    Scenario: Every focused delivery collection covers all exact Project members
      Given a projected Project has delivery facts in two member Repositories and an unrelated Repository
      When the browser queries each focused delivery collection
      Then Candidates, obligations, merge snapshots, and ReleaseSets stay within the exact Project

  Rule: Nested evidence has its own bounded detail route

    @UI-GWT-17
    Scenario: Candidate impacts, verification evidence, and merge authorizations page independently
      Given projected delivery details contain multiple supporting facts
      When the browser queries each focused delivery detail with a one-item evidence page
      Then every detail stays typed and advertises only its own next evidence page

  Rule: Operation batches remain global

    @UI-GWT-18
    Scenario: Batch outcomes are not attributed from command arguments
      Given projected operation batches contain commands mentioning separate projects
      When the browser queries global operation batches
      Then typed batch outcomes are presented without inferred project ownership or raw arguments
