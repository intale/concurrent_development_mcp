# frozen_string_literal: true

RSpec.describe Coordinator::Write::CommandCompletionBuilder do
  subject(:builder) { described_class.new }

  let(:command) do
    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "cmd-100",
      actor: Coordinator::Write::Commands::Actor.new(kind: "user", id: "user-1"),
      change_set_id: "CS-100",
      goal: "Coordinate an API change",
      acceptance_criteria: [ "Producer and consumer remain compatible" ]
    )
  end
  let(:stream) do
    Coordinator::Write::PgStreamFactory.new.call(Coordinator::Write::StreamFactory.new.change_set("CS-100"))
  end
  let(:persisted_events) do
    [
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000001",
        type: "ChangeSetCreated",
        stream:,
        stream_revision: 0
      ),
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000002",
        type: "ChangeSetAcceptanceCriteriaDefined",
        stream:,
        stream_revision: 1
      )
    ]
  end

  it "builds a strict replayable completion from exact persisted references" do
    completion = builder.create_change_set(
      command:,
      input_digest: "sha256:#{"0" * 64}",
      persisted_events:,
      completed_at: "2026-08-20T14:10:00.000000Z"
    )

    expect(completion).to be_a(Coordinator::Write::Events::CommandCompletedV1)
    expect(completion.receipt).to eq("cmd-100")
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: "CS-100")
    )
    expect(completion.emitted_events.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(completion.to_h).not_to include(:projection_barriers, :context_token)
    expect(completion.next_actions).to be_empty
  end

  it "rejects non-persisted references before building the completion" do
    expect do
      builder.create_change_set(
        command:,
        input_digest: "sha256:#{"0" * 64}",
        persisted_events: [ PgEventstore::Event.new ],
        completed_at: "2026-08-20T14:10:00.000000Z"
      )
    end.to raise_error(ArgumentError, /persisted_events/)
  end

  it "records exact WorkItem event references without projection state" do
    work_item_command = Coordinator::Write::Commands::CreateWorkItem.new(
      command_id: "cmd-200",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      repository_id: "billing",
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ]
    )
    stream_factory = Coordinator::Write::StreamFactory.new
    pg_stream_factory = Coordinator::Write::PgStreamFactory.new
    work_item_stream = pg_stream_factory.call(stream_factory.work_item("W-200"))
    change_set_stream = pg_stream_factory.call(stream_factory.change_set("CS-100"))
    events = [
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000010",
        type: "WorkItemCreated",
        stream: work_item_stream,
        stream_revision: 0
      ),
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000011",
        type: "WorkItemAddedToChangeSet",
        stream: change_set_stream,
        stream_revision: 2
      )
    ]

    completion = builder.work_item_create(
      command: work_item_command,
      input_digest: "sha256:#{"1" * 64}",
      persisted_events: events,
      completed_at: "2026-08-20T14:12:00.000000Z"
    )

    expect(completion.tool_name).to eq("work_item_create")
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::WorkItem.new(
        change_set_id: "CS-100",
        work_item_id: "W-200"
      )
    )
    expect(completion.emitted_events.map(&:type)).to eq(
      [ "WorkItemCreated", "WorkItemAddedToChangeSet" ]
    )
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_revision ] }).to eq(
      [ [ "WorkItem", 0 ], [ "ChangeSet", 2 ] ]
    )
    expect(completion.next_actions).to be_empty
  end

  it "builds a dependency receipt from its exact ChangeSet revision" do
    dependency_command = Coordinator::Write::Commands::DeclareWorkItemDependency.new(
      command_id: "cmd-230",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100",
      dependency_id: "DEP-1",
      producer_work_item_id: "W-100",
      consumer_work_item_id: "W-200",
      dependency_kind: "requires_candidate",
      required_output: nil
    )
    event = PgEventstore::Event.new(
      id: "018fd0f0-0000-7000-8000-000000000020",
      type: "WorkItemDependencyDeclared",
      stream: Coordinator::Write::PgStreamFactory.new.call(Coordinator::Write::StreamFactory.new.change_set("CS-100")),
      stream_revision: 4
    )

    completion = builder.work_item_dependency_declare(
      command: dependency_command,
      input_digest: "sha256:#{"2" * 64}",
      persisted_events: [ event ],
      completed_at: "2026-08-20T14:14:00.000000Z"
    )

    expect(completion.tool_name).to eq("work_item_dependency_declare")
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::Dependency.new(
        change_set_id: "CS-100",
        dependency_id: "DEP-1"
      )
    )
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_revision ] }).to eq(
      [ [ "ChangeSet", 4 ] ]
    )
    expect(completion.next_actions).to be_empty
  end

  it "builds activation data and an available-read context action" do
    activation_command = Coordinator::Write::Commands::ActivateChangeSet.new(
      command_id: "cmd-250",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "planner-1"),
      change_set_id: "CS-100"
    )
    event = PgEventstore::Event.new(
      id: "018fd0f0-0000-7000-8000-000000000030",
      type: "ChangeSetActivated",
      stream:,
      stream_revision: 5
    )

    completion = builder.change_set_activate(
      command: activation_command,
      input_digest: "sha256:#{"3" * 64}",
      persisted_events: [ event ],
      completed_at: "2026-08-20T14:15:00.000000Z"
    )

    expect(completion.tool_name).to eq("change_set_activate")
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::ChangeSet.new(change_set_id: "CS-100")
    )
    expect(completion.next_actions).to contain_exactly(
      Coordinator::Write::NextAction.new(
        tool: "coord_context",
        arguments: Coordinator::Write::NextAction::ChangeSetArguments.new(change_set_id: "CS-100")
      )
    )
    ::MCP::Tool::InputSchema.new(Coordinator::Mcp::Schemas.coord_context)
      .validate_arguments(completion.next_actions.sole.arguments.to_h)
  end

  it "builds an Attempt-scoped acquisition receipt with exact event references" do
    acquisition_command = Coordinator::Write::Commands::AcquireWorkItem.new(
      command_id: "cmd-300",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [
        Coordinator::Write::RepositorySnapshotV1.new(
          repository_id: "billing",
          object_format: "sha1",
          commit_oid: "0123456789abcdef0123456789abcdef01234567"
        )
      ]
    )
    stream_factory = Coordinator::Write::StreamFactory.new
    pg_stream_factory = Coordinator::Write::PgStreamFactory.new
    work_item_stream = pg_stream_factory.call(stream_factory.work_item("W-200"))
    attempt_stream = pg_stream_factory.call(stream_factory.attempt("A-300"))
    events = [
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000040",
        type: "WorkItemAcquired",
        stream: work_item_stream,
        stream_revision: 2
      ),
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000041",
        type: "AttemptAuthorized",
        stream: attempt_stream,
        stream_revision: 0
      ),
      PgEventstore::Event.new(
        id: "018fd0f0-0000-7000-8000-000000000042",
        type: "AttemptStarted",
        stream: attempt_stream,
        stream_revision: 1
      )
    ]

    completion = builder.work_item_acquire(
      command: acquisition_command,
      input_digest: "sha256:#{"4" * 64}",
      persisted_events: events,
      completed_at: "2026-08-20T14:20:00.000000Z"
    )

    attempt_arguments = Coordinator::Write::NextAction::AttemptArguments.new(
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300"
    )
    expect(completion.data).to eq(
      Coordinator::Write::CommandReceiptData::Attempt.new(attempt_arguments.to_h)
    )
    expect(completion.next_actions).to be_empty
    expect(completion.emitted_events.map(&:type)).to eq(
      [ "WorkItemAcquired", "AttemptAuthorized", "AttemptStarted" ]
    )
    expect(completion.emitted_events.map { [ _1.stream_name, _1.stream_revision ] }).to eq(
      [ [ "WorkItem", 2 ], [ "Attempt", 0 ], [ "Attempt", 1 ] ]
    )
  end
end
