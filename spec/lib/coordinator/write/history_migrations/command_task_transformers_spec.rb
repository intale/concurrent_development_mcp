# frozen_string_literal: true

RSpec.describe "history migration command and Task transformations", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:old_command_id) { "legacy-command-101" }
  let(:old_task_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:allocator) do
    Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store:)
  end
  let(:locator) do
    Coordinator::Write::HistoryMigrations::LegacyCommandEventLocator.new(event_store:)
  end
  let(:submission_resolver) do
    Coordinator::Write::HistoryMigrations::LegacyCoordinationTaskSubmissionResolver.new(
      event_store:,
      command_event_locator: locator
    )
  end
  let(:submitted_transformer) do
    Coordinator::Container["history_migrations.coordination_task_submitted_v2_transformer"]
  end
  let(:completed_transformer) do
    Coordinator::Write::HistoryMigrations::CommandCompletedV1Transformer.new(
      stream_identity_allocator: allocator,
      submission_resolver:
    )
  end
  let(:lifecycle_transformer) do
    Coordinator::Write::HistoryMigrations::CoordinationTaskLifecycleTransformer.new(
      stream_identity_allocator: allocator,
      submission_resolver:
    )
  end
  let(:command_input) do
    Coordinator::Write::CommandInputDocuments::CreateChangeSetV1.new(
      schema: "command-input/v1",
      command_id: old_command_id,
      tool_name: "change_set_create",
      input: Coordinator::Write::CommandInputDocuments::CreateChangeSetInputV1.new(
        actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
          actor_kind: "agent",
          actor_id: "agent-luna-a"
        ),
        change_set_id: "legacy-change-set",
        goal: "Migrate the command history",
        acceptance_criteria: [ "Command and Task facts remain linked" ]
      )
    )
  end
  let(:submitted_payload) do
    Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskSubmittedV2.new(
      task_id: old_task_id,
      tool_name: "change_set_create",
      command_id: old_command_id,
      command_input:,
      submitted_at: "2026-08-01T10:00:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
  end

  before { persist_change_set }

  it "Given a successful legacy Task, when facts are transformed, then one UUIDv7 command links its request and terminal state" do
    submitted_event = persist_task(submitted_payload)
    completion_event = persist_command(command_completion_payload)
    upper_position = completion_event.global_position

    submission = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: submitted_event,
      source_payload: submitted_payload
    ).value!
    completion = completed_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: completion_event,
      source_payload: command_completion_payload
    ).value!

    registration, task = submission
    terminal = completion.sole
    expect([ registration.event.class, task.event.class, terminal.event.class ]).to eq(
      [
        Coordinator::Write::Events::CommandRegisteredV1,
        Coordinator::Write::Events::CoordinationTaskSubmittedV3,
        Coordinator::Write::Events::CommandSucceededV1
      ]
    )
    expect(registration.target_stream).to eq(terminal.target_stream)
    expect(registration.event.command_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task.event.command_id).to eq(registration.event.command_id)
    expect(task.event.command_input.command_id).to eq(registration.event.command_id)
    expect(task.event.task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task.event.task_id).not_to eq(old_task_id)
    expect(registration.event.request_id).to eq(submitted_event.global_position)
    expect(registration.metadata_extension.canonical_input_digest).to eq(
      task.metadata_extension.canonical_input_digest
    )
    target_command = Coordinator::Write::Tasks::TargetCommandBuilder.new.call(task.event.command_input)
    expect(task.metadata_extension.canonical_input_digest).to eq(
      Coordinator::Write::CommandInputDigest.new.request(target_command)
    )
    expect(submission.flat_map { _1.event.to_h.keys }).not_to include(:submitted_at)
  end

  it "Given a legacy domain rejection, when the completed Task is transformed, then its command becomes terminal without retaining its result dump" do
    submitted_event = persist_task(submitted_payload)
    completed_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskCompletedV2.new(
      task_id: old_task_id,
      result: domain_rejection,
      completed_at: "2026-08-01T10:02:00.000000Z"
    )
    completed_event = persist_task(completed_payload)
    registration = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completed_event.global_position,
      source_event: submitted_event,
      source_payload: submitted_payload
    ).value!.first

    facts = lifecycle_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completed_event.global_position,
      source_event: completed_event,
      source_payload: completed_payload
    ).value!

    rejected, completed = facts
    expect(rejected.target_stream).to eq(registration.target_stream)
    expect(rejected.event).to eq(
      Coordinator::Write::Events::CommandRejectedV1.new(
        command_id: registration.event.command_id,
        code: "change_set_already_exists",
        reason: "ChangeSet already exists",
        retryable: false
      )
    )
    expect(completed.event).to eq(
      Coordinator::Write::Events::CoordinationTaskCompletedV3.new(task_id: completed.target_stream.stream_id)
    )
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(:result, :completed_at)
  end

  it "Given identical legacy retries, when their Task histories are transformed, then only the earliest Task remains" do
    first_submission = persist_task(submitted_payload)
    completion = persist_command(command_completion_payload)
    retry_task_id = SecureRandom.uuid_v7
    retry_payload = submitted_payload.class.new(
      submitted_payload.to_h.merge(task_id: retry_task_id)
    )
    retry_submission = persist_task(retry_payload)
    retry_started_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::
      CoordinationTaskExecutionStartedV1.new(
        task_id: retry_task_id,
        started_at: "2026-08-01T10:03:00.000000Z"
      )
    retry_started = persist_task(retry_started_payload)
    upper_position = retry_started.global_position

    first_facts = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: first_submission,
      source_payload: submitted_payload
    ).value!
    retry_facts = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: retry_submission,
      source_payload: retry_payload
    ).value!
    retry_lifecycle_facts = lifecycle_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: retry_started,
      source_payload: retry_started_payload
    ).value!
    terminal = completed_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: completion,
      source_payload: command_completion_payload
    ).value!

    expect(first_facts.map { _1.event.class }).to eq(
      [
        Coordinator::Write::Events::CommandRegisteredV1,
        Coordinator::Write::Events::CoordinationTaskSubmittedV3
      ]
    )
    expect(retry_facts).to be_empty
    expect(retry_lifecycle_facts).to be_empty
    expect(terminal.map { _1.event.class }).to eq([ Coordinator::Write::Events::CommandSucceededV1 ])
  end

  it "Given a legacy Command ID reused with different input, when both requests are transformed, then each has its own command lifecycle" do
    first_correlation_id = SecureRandom.uuid_v7
    retry_correlation_id = SecureRandom.uuid_v7
    first_submission = persist_task(submitted_payload, correlation_id: first_correlation_id)
    first_completed_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::
      CoordinationTaskCompletedV2.new(
        task_id: old_task_id,
        result: domain_rejection,
        completed_at: "2026-08-01T10:02:00.000000Z"
      )
    first_completed = persist_task(
      first_completed_payload,
      correlation_id: first_correlation_id
    )
    retry_task_id = SecureRandom.uuid_v7
    conflicting_input = command_input.class.new(
      command_input.to_h.merge(
        input: command_input.input.class.new(
          command_input.input.to_h.merge(goal: "A different request under the reused Command ID")
        )
      )
    )
    retry_payload = submitted_payload.class.new(
      submitted_payload.to_h.merge(task_id: retry_task_id, command_input: conflicting_input)
    )
    retry_submission = persist_task(retry_payload, correlation_id: retry_correlation_id)
    completion_payload = command_completion_payload
    completion = persist_command(completion_payload, correlation_id: retry_correlation_id)
    upper_position = completion.global_position

    first_request = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: first_submission,
      source_payload: submitted_payload
    ).value!
    first_terminal = lifecycle_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: first_completed,
      source_payload: first_completed_payload
    ).value!.first
    retry_request = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: retry_submission,
      source_payload: retry_payload
    ).value!
    retry_terminal = completed_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: completion,
      source_payload: completion_payload
    ).value!.sole

    first_registration = first_request.first
    retry_registration = retry_request.first
    expect(first_registration.target_stream).to eq(first_terminal.target_stream)
    expect(retry_registration.target_stream).to eq(retry_terminal.target_stream)
    expect(first_registration.target_stream).not_to eq(retry_registration.target_stream)
    expect(first_registration.event.request_id).to eq(first_submission.global_position)
    expect(retry_registration.event.request_id).to eq(retry_submission.global_position)
    expect([ first_terminal.event.class, retry_terminal.event.class ]).to eq(
      [
        Coordinator::Write::Events::CommandRejectedV1,
        Coordinator::Write::Events::CommandSucceededV1
      ]
    )
  end

  it "Given a standalone legacy command, when it is transformed, then a valid registration precedes its terminal fact" do
    source_payload = command_completion_payload(command_id: "internal:standalone-command")
    source_event = persist_command(source_payload)

    facts = completed_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: source_event.global_position,
      source_event:,
      source_payload:
    ).value!

    registration, terminal = facts
    expect(registration.event).to be_a(Coordinator::Write::Events::CommandRegisteredV1)
    expect(registration.event.request_id).to eq(source_event.global_position)
    expect(terminal.event).to eq(
      Coordinator::Write::Events::CommandSucceededV1.new(command_id: registration.event.command_id)
    )
    expect(registration.metadata_extension.canonical_input_digest).to eq(source_payload.canonical_input_digest)
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(
      :data,
      :summary,
      :completed_at,
      :emitted_events
    )
  end

  it "Given legacy Task lifecycle facts, when they are transformed, then occurrence copies are removed and failure semantics remain" do
    persist_task(submitted_payload)
    payloads = [
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskExecutionStartedV1.new(
        task_id: old_task_id,
        started_at: "2026-08-01T10:01:00.000000Z"
      ),
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskCancellationRequestedV1.new(
        task_id: old_task_id,
        requested_at: "2026-08-01T10:02:00.000000Z"
      ),
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskCancelledV1.new(
        task_id: old_task_id,
        reason: "cancelled_before_execution",
        cancelled_at: "2026-08-01T10:03:00.000000Z"
      ),
      Coordinator::Write::HistoryMigrations::LegacyEvents::CoordinationTaskFailedV1.new(
        task_id: old_task_id,
        error: Coordinator::Write::Tasks::JsonRpcErrorV1.new(code: -32_603, message: "Internal error"),
        failed_at: "2026-08-01T10:04:00.000000Z"
      )
    ]
    events = payloads.map { persist_task(_1) }

    facts = payloads.zip(events).flat_map do |payload, event|
      lifecycle_transformer.call(
        migration_id:,
        source_config_name: "default",
        source_upper_position: events.last.global_position,
        source_event: event,
        source_payload: payload
      ).value!
    end

    expect(facts.map { _1.event.class }).to eq(
      [
        Coordinator::Write::Events::CoordinationTaskExecutionStartedV2,
        Coordinator::Write::Events::CoordinationTaskCancellationRequestedV2,
        Coordinator::Write::Events::CoordinationTaskCancelledV2,
        Coordinator::Write::Events::CoordinationTaskFailedV2
      ]
    )
    expect(facts.map(&:target_stream).uniq.one?).to be(true)
    expect(facts.last.event).to have_attributes(
      code: "internal_error",
      reason: "Internal error",
      retryable: false
    )
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(
      :started_at,
      :requested_at,
      :cancelled_at,
      :failed_at
    )
  end

  def command_completion_payload(command_id: old_command_id)
    Coordinator::Write::HistoryMigrations::LegacyEvents::CommandCompletedV1.new(
      command_id:,
      tool_name: "change_set_create",
      canonical_input_digest: "sha256:#{'a' * 64}",
      status: "ok",
      summary: "ChangeSet created.",
      receipt: command_id,
      data: Coordinator::Write::CommandReceiptData::ChangeSet.new(
        change_set_id: "legacy-change-set"
      ),
      warnings: [],
      next_actions: [],
      emitted_events: [],
      completed_at: "2026-08-01T10:01:00.000000Z"
    )
  end

  def domain_rejection
    Coordinator::Write::Tasks::SemanticResultV1::DomainRejection.new(
      kind: "domain_rejection",
      status: "denied",
      summary: "ChangeSet already exists",
      command_id: old_command_id,
      error: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
        code: "change_set_already_exists",
        message: "ChangeSet already exists",
        details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(
          change_set_id: "legacy-change-set"
        )
      ),
      next_actions: []
    )
  end

  def persist_task(payload, correlation_id: self.correlation_id)
    persist(
      payload,
      stream: Coordinator::Write::StreamReference.new(
        context: "CoordinatorControl",
        stream_name: "CoordinationTask",
        stream_id: payload.task_id
      ),
      markers: [ "task:#{payload.task_id}", "command:#{old_command_id}" ],
      correlation_id:
    )
  end

  def persist_change_set
    payload = Coordinator::Write::Events::ChangeSetCreatedV1.new(
      change_set_id: "legacy-change-set",
      goal: "Migrate the command history",
      created_at: "2026-08-01T09:59:00.000000Z"
    )
    persist(
      payload,
      stream: Coordinator::Write::StreamReference.new(
        context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        stream_id: "legacy-change-set"
      ),
      markers: [ "change-set:legacy-change-set" ]
    )
  end

  def persist_command(payload, correlation_id: self.correlation_id)
    persist(
      payload,
      stream: Coordinator::Write::StreamReference.new(
        context: "CoordinatorControl",
        stream_name: "Command",
        stream_id: payload.command_id
      ),
      markers: [ "command:#{payload.command_id}" ],
      correlation_id:
    )
  end

  def persist(payload, stream:, markers:, correlation_id: self.correlation_id)
    event_store.append(
      stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => old_command_id,
            "actor_kind" => "agent",
            "actor_id" => "agent-luna-a",
            "recorded_by" => "coordinator"
          },
          markers:,
          correlation_id:
        )
      ]
    ).sole
  end
end
