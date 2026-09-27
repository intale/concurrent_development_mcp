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
  let(:transformer_registry) { Coordinator::Container["history_migrations.transformer_registry"] }
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

  it "preserves an absent entity reference submitted by a rejected legacy Task" do
    missing_repository_id = SecureRandom.uuid_v7
    input = resource_resolution_input(missing_repository_id)
    source = submitted_payload.class.new(
      submitted_payload.to_h.merge(tool_name: "resource_resolve", command_input: input)
    )
    submitted_event = persist_task(source)
    completed_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::
      CoordinationTaskCompletedV2.new(
        task_id: old_task_id,
        result: domain_rejection,
        completed_at: "2026-08-01T10:02:00.000000Z"
      )
    completed_event = persist_task(completed_payload)

    result = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completed_event.global_position,
      source_event: submitted_event,
      source_payload: source
    )

    expect(result).to be_success
    migrated = result.value!.last.event.command_input
    expect(migrated).to be_a(Coordinator::Write::CommandInputDocuments::ResolveResourceV1)
    expect(migrated.input.repository_id).to eq(missing_repository_id)
  end

  it "allocates stable UUIDv7 references for absent legacy Artifacts in a rejected Task" do
    source = submitted_payload.class.new(
      submitted_payload.to_h.merge(
        tool_name: "development_artifact_capture",
        command_input: legacy_artifact_capture_command_input.to_h
      )
    )
    submitted_event = persist_task(source)
    completed_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::
      CoordinationTaskCompletedV2.new(
        task_id: old_task_id,
        result: domain_rejection,
        completed_at: "2026-08-01T10:02:00.000000Z"
      )
    completed_event = persist_task(completed_payload)

    transformations = 2.times.map do
      submitted_transformer.call(
        migration_id:,
        source_config_name: "default",
        source_upper_position: completed_event.global_position,
        source_event: submitted_event,
        source_payload: source
      )
    end

    expect(transformations).to all(be_success)
    facts = transformations.map(&:value!)
    artifacts = facts.map { _1.last.event.command_input.input.artifact }
    expect(artifacts.map(&:artifact_id).uniq.one?).to be(true)
    expect(artifacts.map(&:observation_id).uniq.one?).to be(true)
    expect(artifacts.first.artifact_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(artifacts.first.observation_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(artifacts.first.artifact_id).not_to eq(artifacts.first.observation_id)
    expect(facts.flatten.map { _1.event.class }).to all(
      be_in(
        [
          Coordinator::Write::Events::CommandRegisteredV1,
          Coordinator::Write::Events::CoordinationTaskSubmittedV3
        ]
      )
    )
  end

  it "preserves an absent legacy lease set and its references in a rejected Task" do
    work_item_id = "legacy-work-item"
    attempt_id = "legacy-attempt"
    lease_set_id = SecureRandom.uuid_v7
    lease_id = SecureRandom.uuid_v7
    resource_id = SecureRandom.uuid_v7
    persist_reference_root("DevelopmentExecution", "WorkItem", work_item_id, "WorkItemCreated")
    persist_reference_root("DevelopmentExecution", "Attempt", attempt_id, "AttemptAuthorized")
    persist_reference_root(
      "DevelopmentCoordination",
      "Resource",
      resource_id,
      "ResourceRegistered"
    )
    input = legacy_lease_renewal_command_input(
      work_item_id:,
      attempt_id:,
      lease_set_id:,
      lease_id:,
      resource_id:
    )
    source = submitted_payload.class.new(
      submitted_payload.to_h.merge(tool_name: "lease_renew", command_input: input.to_h)
    )
    submitted_event = persist_task(source)
    completed_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::
      CoordinationTaskCompletedV2.new(
        task_id: old_task_id,
        result: domain_rejection,
        completed_at: "2026-08-01T10:02:00.000000Z"
      )
    completed_event = persist_task(completed_payload)

    result = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completed_event.global_position,
      source_event: submitted_event,
      source_payload: source
    )

    expect(result).to be_success
    migrated = result.value!.last.event.command_input
    reference = migrated.input.intentions.sole
    expect(migrated).to be_a(Coordinator::Write::CommandInputDocuments::RenewLeaseSetV1)
    expect(migrated.input.intention_set_id).to eq(lease_set_id)
    expect(reference).to have_attributes(
      intention_id: lease_id,
      resource_id: a_string_matching(Coordinator::Shared::Types::UUID_V7_PATTERN),
      fencing_token: 17
    )
    expect(reference.resource_id).not_to eq(resource_id)
  end

  it "rejects an absent entity reference attributed to a successful legacy Task" do
    missing_repository_id = SecureRandom.uuid_v7
    input = resource_resolution_input(missing_repository_id)
    source = submitted_payload.class.new(
      submitted_payload.to_h.merge(tool_name: "resource_resolve", command_input: input)
    )
    submitted_event = persist_task(source)
    completed_payload = Coordinator::Write::HistoryMigrations::LegacyEvents::
      CoordinationTaskCompletedV2.new(
        task_id: old_task_id,
        result: Coordinator::Write::Tasks::SemanticResultV1::Success.new(
          kind: "success",
          summary: "Resource resolved",
          command_id: old_command_id,
          receipt: old_command_id,
          data: Coordinator::Write::CommandReceiptData::ResourceResolution.new(
            resource_id: SecureRandom.uuid_v7,
            repository_id: missing_repository_id,
            kind: "file",
            normalized_path: "README.md",
            outcome: "registered",
            registered_at: "2026-08-01T10:02:00.000000Z",
            bound_at: "2026-08-01T10:02:00.000000Z"
          ),
          warnings: [],
          next_actions: []
        ),
        completed_at: "2026-08-01T10:02:00.000000Z"
      )
    completed_event = persist_task(completed_payload)

    result = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completed_event.global_position,
      source_event: submitted_event,
      source_payload: source
    )

    expect(result).to be_failure
    expect(result.failure).to have_attributes(code: :ambiguous_source_reference)
    expect(result.failure.message).to include("Historical source reference is absent")
  end

  it "rebinds an embedded legacy Artifact relation to its transformed relation stream" do
    artifact_id = "artifact:v1:#{'b' * 64}"
    relation_id = "artifact-relation:v1:#{'c' * 64}"
    artifact_stream = Coordinator::Write::StreamReference.new(
      context: "DevelopmentMemory",
      stream_name: "DevelopmentArtifact",
      stream_id: artifact_id
    )
    persist(
      legacy_artifact_capture(artifact_id),
      stream: artifact_stream,
      markers: [ "development-artifact:#{artifact_id}" ]
    )
    command_input = legacy_relation_command_input(artifact_id:, relation_id:)
    source = submitted_payload.class.new(
      submitted_payload.to_h.merge(
        tool_name: "development_artifact_relation_declare",
        command_input: command_input.to_h
      )
    )
    submitted_event = persist_task(source)
    declaration = legacy_relation_declaration(artifact_id:, relation_id:)
    declaration_event = persist(
      declaration,
      stream: artifact_stream,
      markers: [
        "development-artifact:#{artifact_id}",
        "development-artifact-relation:#{relation_id}"
      ],
      metadata: { "policy_version" => "development-artifact-repository/v1" }
    )
    upper_position = declaration_event.global_position

    relation_fact = transformer_registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: declaration_event
    ).value!.sole
    task_fact = submitted_transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: submitted_event,
      source_payload: source
    ).value!.last
    migrated_relation = task_fact.event.command_input.input.artifact_relation

    expect(migrated_relation).to have_attributes(
      relation_id: relation_fact.target_stream.stream_id,
      source_artifact_id: relation_fact.event.source_artifact_id
    )
    expect(migrated_relation.relation_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(migrated_relation.relation_id).not_to eq(relation_id)
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

  def resource_resolution_input(repository_id)
    Coordinator::Write::CommandInputDocuments::ResolveResourceV1.new(
      schema: "command-input/v1",
      command_id: old_command_id,
      tool_name: "resource_resolve",
      input: Coordinator::Write::CommandInputDocuments::ResolveResourceInputV1.new(
        actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
          actor_kind: "agent",
          actor_id: "agent-luna-a"
        ),
        repository_id:,
        kind: "file",
        path: "README.md"
      )
    )
  end

  def legacy_artifact_capture(artifact_id)
    content = Coordinator::Write::Content::TextV1.new(
      encoding: "utf-8",
      media_type: "text/markdown",
      text: "Artifact\n",
      content_sha256: "sha256:#{'d' * 64}",
      byte_size: 9
    )
    source = Coordinator::Write::DevelopmentArtifacts::SourceV1.new(
      kind: "local_file",
      locator: "docs/artifact.md",
      revision: nil,
      observed_at: "2026-08-01T10:00:00.000000Z",
      collector: "legacy-import/v1"
    )
    artifact = Coordinator::Write::HistoryMigrations::LegacyDevelopmentArtifacts::ArtifactV2.new(
      artifact_id:,
      scope: "project:test",
      title: "Artifact",
      kind: "documentation",
      labels: [],
      content:,
      source:
    )
    Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactCapturedV2.new(
      artifact:,
      captured_at: "2026-08-01T10:00:00.000000Z"
    )
  end

  def legacy_artifact_capture_command_input
    content = Coordinator::Write::Content::TextV1.new(
      encoding: "utf-8",
      media_type: "text/markdown",
      text: "Artifact\n",
      content_sha256: "sha256:#{'d' * 64}",
      byte_size: 9
    )
    source = Coordinator::Write::CommandInputDocuments::DevelopmentArtifactSourceV1.new(
      kind: "local_file",
      locator: "docs/artifact.md",
      revision: nil,
      observed_at: "2026-08-01T10:00:00.000000Z",
      collector: "legacy-import/v1"
    )
    artifact = Coordinator::Write::HistoryMigrations::LegacyCommandInputDocuments::
      DevelopmentArtifactV2.new(
        artifact_id: "artifact:v1:#{'b' * 64}",
        observation_id: "artifact-observation:v1:#{'c' * 64}",
        scope: "project:test",
        title: "Artifact",
        kind: "documentation",
        labels: [],
        content:,
        source:
      )
    Coordinator::Write::HistoryMigrations::LegacyCommandInputDocuments::
      CaptureDevelopmentArtifactV2.new(
        schema: "command-input/v2",
        command_id: old_command_id,
        tool_name: "development_artifact_capture",
        input: Coordinator::Write::HistoryMigrations::LegacyCommandInputDocuments::
          CaptureDevelopmentArtifactInputV2.new(
            actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
              actor_kind: "agent",
              actor_id: "agent-luna-a"
            ),
            artifact:
          )
      )
  end

  def legacy_lease_renewal_command_input(
    work_item_id:,
    attempt_id:,
    lease_set_id:,
    lease_id:,
    resource_id:
  )
    input = Coordinator::Write::HistoryMigrations::PostRemodelCommandInputDocuments::
      LegacyRenewLeaseSetInputV1.new(
        actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
          actor_kind: "agent",
          actor_id: "agent-luna-a"
        ),
        change_set_id: "legacy-change-set",
        work_item_id:,
        attempt_id:,
        lease_set_id:,
        leases: [
          Coordinator::Write::HistoryMigrations::PostRemodelCommandInputDocuments::
            LegacyResourceLeaseReferenceV1.new(
              resource_id:,
              lease_id:,
              fencing_token: 17
            )
        ],
        lease_duration_seconds: 3_600
      )
    Coordinator::Write::HistoryMigrations::PostRemodelCommandInputDocuments::
      LegacyRenewLeaseSetV1.new(
        schema: "command-input/v1",
        command_id: old_command_id,
        tool_name: "lease_renew",
        input:
      )
  end

  def legacy_relation_command_input(artifact_id:, relation_id:)
    relation = Coordinator::Write::HistoryMigrations::LegacyCommandInputDocuments::
      DevelopmentArtifactRelationV1.new(
        relation_id:,
        source_artifact_id: artifact_id,
        relation: "references",
        target: Coordinator::Write::CommandInputDocuments::DevelopmentArtifactRelationTargetV1.new(
          kind: "external",
          id: "https://example.test/reference"
        ),
        attributes: Coordinator::Write::CommandInputDocuments::
          DevelopmentArtifactRelationAttributesV1.new(path: "reference")
      )
    Coordinator::Write::HistoryMigrations::LegacyCommandInputDocuments::
      DeclareDevelopmentArtifactRelationV1.new(
        schema: "command-input/v1",
        command_id: old_command_id,
        tool_name: "development_artifact_relation_declare",
        input: Coordinator::Write::HistoryMigrations::LegacyCommandInputDocuments::
          DeclareDevelopmentArtifactRelationInputV1.new(
            actor: Coordinator::Write::CommandInputDocuments::ActorV1.new(
              actor_kind: "agent",
              actor_id: "agent-luna-a"
            ),
            artifact_relation: relation,
            supersedes_relation_id: nil,
            supersession_reason: nil
          )
      )
  end

  def legacy_relation_declaration(artifact_id:, relation_id:)
    relation = Coordinator::Write::HistoryMigrations::LegacyDevelopmentArtifacts::RelationV1.new(
      relation_id:,
      source_artifact_id: artifact_id,
      relation: "references",
      target: Coordinator::Write::DevelopmentArtifacts::RelationTargetV1.new(
        kind: "external",
        id: "https://example.test/reference",
        status: "verified"
      ),
      attributes: Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1.new(
        path: "reference"
      )
    )
    Coordinator::Write::HistoryMigrations::LegacyEvents::DevelopmentArtifactRelationDeclaredV1.new(
      artifact_relation: relation,
      declared_at: "2026-08-01T10:01:00.000000Z"
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

  def persist_reference_root(context, stream_name, stream_id, event_type)
    event_store.append(
      Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: event_type,
          data: {},
          metadata: {
            "schema_version" => 1,
            "command_id" => old_command_id,
            "actor_kind" => "agent",
            "actor_id" => "agent-luna-a",
            "recorded_by" => "coordinator"
          },
          markers: [],
          correlation_id:
        )
      ]
    ).sole
  end

  def persist(payload, stream:, markers:, correlation_id: self.correlation_id, metadata: {})
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
          }.merge(metadata),
          markers:,
          correlation_id:
        )
      ]
    ).sole
  end
end
