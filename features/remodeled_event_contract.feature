@wip @remodeled-event-contract
Feature: Cohesive event facts
  Coordination history records durable facts instead of transport documents or aggregate snapshots.
  Event time and tracing come from the native event envelope.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A command emits only the facts established by its decision

    Scenario: Completing a WorkItem records its relationships before its terminal fact
      Given an agent owns an active Attempt with a submitted Candidate and recorded outputs
      When the agent completes the WorkItem through MCP
      Then each output is recorded as a separate WorkItem output fact
      And the selected Candidate is recorded as a separate WorkItem relationship fact
      And the Attempt and WorkItem completion facts contain only their lifecycle identities
      And the Task result is reconstructed on the read side rather than copied into either completion fact

    Scenario Outline: A terminal fact contains no occurrence-time or aggregate snapshot fields
      Given a command can establish a terminal <subject> fact
      When the command completes the <subject> through MCP
      Then the persisted <event> data contains only its <identity> identity
      And its occurrence time is the native Event created_at
      And its data contains no completed_at, added_at, selected_at, content, or structured_content dump

      Examples:
        | subject           | event                         | identity      |
        | Command           | CommandSucceeded              | command_id    |
        | Coordination Task | CoordinationTaskCompleted     | task_id       |
        | ChangeSet         | ChangeSetCompleted            | change_set_id |
        | WorkItem          | WorkItemCompleted             | work_item_id  |
        | Attempt           | AttemptCompleted              | attempt_id    |
        | Operation Batch   | OperationBatchCompleted       | batch_id      |
        | ReleaseSet        | ReleaseSetCompleted            | release_set_id|

  Rule: Mutable properties have cohesive facts

    Scenario: Updating Development Artifact content changes one property
      Given a Development Artifact has a stable UUIDv7 identity and projected text content
      When an agent changes its text through MCP
      Then one DevelopmentArtifactContentChanged fact carries only the artifact identity and text bytes in data
      And encoding, media type, byte size, and server-computed content digest are typed event metadata
      And unchanged scope, title, kind, labels, and source are not copied into the event

    Scenario: One command can atomically establish several related facts
      Given an agent submits a new Candidate with its assignments and evidence
      When the Candidate command establishes facts in several streams
      Then every fact is validated before any fact is written
      And the ordered fact set is committed through one Client multiple transaction
      And every persisted fact was produced by that command

  Rule: Coordinator identity favors UUIDv7 streams and readable selectors

    Scenario: A natural resource identity is allocated without a digest-derived index key
      Given a repository, resource kind, and normalized relative path
      When two agents concurrently resolve the same resource through MCP
      Then both results identify one UUIDv7 Resource stream
      And uniqueness is selected by one canonical readable compound marker
      And no coordinator stream ID or marker is derived from SHA, MD5, or another digest

