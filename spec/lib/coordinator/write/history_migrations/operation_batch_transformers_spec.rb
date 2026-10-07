# frozen_string_literal: true

RSpec.describe "history migration OperationBatch transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:source_batch_id) { SecureRandom.uuid_v7 }
  let(:source_correlation_id) { SecureRandom.uuid_v7 }
  let(:batch_command_id) { "legacy-batch-command" }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-luna-a") }
  let(:manifest_builder) { Coordinator::Write::OperationBatches::ManifestBuilder.new }
  let(:canonical_json) { Coordinator::Write::CanonicalJson.new }
  let(:source_stream) do
    Coordinator::Write::StreamReference.new(
      context: "DevelopmentCoordination",
      stream_name: "OperationBatch",
      stream_id: source_batch_id
    )
  end
  let(:source_items) { build_source_items(2) }

  def build_source_items(count)
    prepared = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(
      command_id: batch_command_id,
      actor: { kind: actor.kind, id: actor.id },
      batch_id: source_batch_id,
      items: count.times.map do |index|
        skill_input(command_id: "legacy-item-#{index}", name: "migration-#{index}")
      end
    ).value!.items
    prepared.map do |item|
      Coordinator::Write::OperationBatches::ItemV1.new(
        index: item.index,
        command_input: item.command_input,
        canonical_input_digest: canonical_json.sha256(item.command_input.to_h)
      )
    end
  end

  it "migrates a mixed legacy Batch into UUIDv7 Batch and Command histories without result dumps" do
    source_events = persist_completed_batch
    upper_position = source_events.last.global_position

    source_events.each { expect(plan(_1, upper_position:)).to be_success }

    creation_facts = transform(source_events.fetch(0), upper_position:).value!
    success_facts = transform(source_events.fetch(2), upper_position:).value!
    rejection_facts = transform(source_events.fetch(3), upper_position:).value!
    completion_fact = transform(source_events.fetch(4), upper_position:).value!.sole

    expect(creation_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::OperationBatchCreatedV2,
      Coordinator::Write::Events::OperationBatchTargetSelectedV1,
      Coordinator::Write::Events::OperationBatchItemEnqueuedV1,
      Coordinator::Write::Events::CommandRegisteredV1,
      Coordinator::Write::Events::OperationBatchItemEnqueuedV1,
      Coordinator::Write::Events::CommandRegisteredV1
    ])
    target_batch_id = creation_facts.first.target_stream.stream_id
    expect(creation_facts.first.metadata_extension.policy_version).to eq("operation-batch/v2")
    expect(target_batch_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(target_batch_id).not_to eq(source_batch_id)
    registrations = creation_facts.select do |fact|
      fact.event.is_a?(Coordinator::Write::Events::CommandRegisteredV1)
    end
    expect(registrations.map { _1.event.request_id }).to eq(%w[legacy-item-0 legacy-item-1])
    expect(registrations.map { _1.event.command_id }).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(success_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::OperationBatchItemSucceededV2,
      Coordinator::Write::Events::OperationBatchItemCompletionLinkedV1
    ])
    expect(rejection_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::CommandRejectedV2,
      Coordinator::Write::Events::OperationBatchItemRejectedV2,
      Coordinator::Write::Events::OperationBatchItemCompletionLinkedV1
    ])
    expect(rejection_facts.fetch(1).event).to have_attributes(
      code: "skill_revision_conflict",
      reason: "Skill revision changed",
      retryable: false
    )
    expect(completion_fact.event).to eq(
      Coordinator::Write::Events::OperationBatchCompletedV2.new(batch_id: target_batch_id)
    )
    transformed = creation_facts + success_facts + rejection_facts + [ completion_fact ]
    expect(transformed.flat_map { _1.event.to_h.keys }).not_to include(
      :result,
      :created_at,
      :finished_at,
      :completed_at,
      :succeeded,
      :rejected,
      :total,
      :items
    )

    writes = source_events.map { dispatch(_1, upper_position:) }
    writes.each { expect(_1).to be_success }
    writes.flat_map { _1.value!.events }.each do |event|
      expect(event.markers.grep(/\Acommand:/)).to eq([ "command:#{event.metadata.fetch('command_id')}" ])
    end
    writes.flat_map { _1.value!.events }.select { _1.stream.stream_name == "OperationBatch" }.each do |event|
      validation = HistoryMigrationProjectionContract.call(event, Coordinator::Read::Contracts::OperationBatchSourceEvent.new)
      expect(validation).to be_success, validation.errors.to_h.inspect
    end
    source_events.each { expect(dispatch(_1, upper_position:).value!.outcome).to eq("existing") }

    batch = Coordinator::Write::OperationBatches::Loader.new(event_store: target_store).call(target_batch_id)
    expect(batch.state).to have_attributes(
      processing_page_size: Coordinator::Shared::Types::OPERATION_BATCH_PAGE_SIZE,
      succeeded_count: 1,
      rejected_count: 1,
      running?: false
    )
    expect(batch.state.items.map(&:request_id)).to eq(%w[legacy-item-0 legacy-item-1])
    terminal_events = target_command_terminals(batch.state.items)
    terminal_events.each do |terminal|
      source = Coordinator::Read::CommandResults::SourceLoader.new(event_store: target_store).call(terminal)
      expect(source).not_to be_nil
      expect(source.persisted_events.map(&:type)).not_to include("OperationBatchItemEnqueued")
      expect(source.persisted_events.map { _1.metadata.fetch("command_id") }).to all(eq(terminal.stream.stream_id))
    end
    expect(batch.state.completion_links.map(&:completion)).to contain_exactly(
      *terminal_events.map { event_reference(_1) }
    )
    command_states = batch.state.items.map do |item|
      Coordinator::Write::CommandLifecycle::Loader.new(event_store: target_store).call(item.command_id).state
    end
    expect(command_states.map(&:status)).to eq(%w[succeeded rejected])
    expect(command_states.last).to have_attributes(
      rejection_code: "skill_revision_conflict",
      rejection_reason: "Skill revision changed",
      rejection_retryable: false
    )
    rejection = Coordinator::Write::EventSchemaRegistry.new.load(
      type: terminal_events.last.type,
      schema_version: terminal_events.last.metadata.fetch("schema_version"),
      data: terminal_events.last.data
    )
    expect(rejection.error).to be_a(
      Coordinator::Write::Tasks::DomainErrorV1::SkillRevisionConflictError
    )
  end

  it "fails closed when the legacy manifest digest does not describe the persisted items" do
    creation = legacy_creation.new(manifest_digest: digest("wrong-manifest"))
    source_event = persist_batch(creation, actor:)

    result = transform(source_event, upper_position: source_event.global_position)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "OperationBatchCreated",
      schema_version: 1,
      source_event_id: source_event.id
    )
  end

  it "resolves only the requested item while keeping its UUID and input aligned with full creation" do
    events = persist_completed_batch
    resolver = Coordinator::Container["history_migrations.operation_batch_context_resolver"]
    common = { migration_id:, source_config_name: "default", source_upper_position: events.last.global_position }

    selected = resolver.from_stream(**common, source_event: events.fetch(2), item_indexes: [ 0 ]).value!
    lifecycle = resolver.from_stream(**common, source_event: events.last, item_indexes: []).value!
    complete = resolver.from_creation(**common, source_event: events.first,
      source_creation: legacy_creation).value!

    expect(selected.items.map(&:index)).to eq([ 0 ])
    expect(selected.items.sole).to eq(complete.item(0))
    expect(lifecycle.items).to be_empty
    expect(lifecycle.batch_id).to eq(complete.batch_id)
  end

  it "still verifies the exact completion revision after loading completion evidence in one bounded query" do
    persist_source_skills(source_items)
    creation = persist_batch(legacy_creation, actor:)
    completion = legacy_command_completion(creation)
    completion_event = persist_command(completion)
    outcome = success_outcome(completion, completion_event:)
    forged = outcome.new(target_completion: outcome.target_completion.new(stream_revision: 1))
    event = persist_batch(forged, actor: system_actor, index: 0, caused_by: completion_event)

    result = transform(event, upper_position: event.global_position)

    expect(result).to be_failure
    expect(result.failure.message).to include("target completion reference is not exact")
  end

  it "maps continuation only after the complete preceding page was recorded" do
    items = build_source_items(51)
    persist_source_skills(items)
    creation_event = persist_batch(legacy_creation(items:), actor:)
    preceding_outcomes = items.take(50).map do |item|
      persist_batch(
        rejection_outcome(item:),
        actor: system_actor,
        index: item.index,
        caused_by: creation_event
      )
    end
    continuation = Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchContinuationRequestedV1.new(
      batch_id: source_batch_id,
      page_start: 50,
      page_end: 50,
      source_event: event_reference(creation_event),
      requested_at: timestamp(5)
    )
    continuation_event = persist_batch(
      continuation,
      actor: system_actor,
      caused_by: preceding_outcomes.last
    )

    fact = transform(continuation_event, upper_position: continuation_event.global_position).value!.sole

    expect(fact.event).to eq(
      Coordinator::Write::Events::OperationBatchContinuationRequestedV2.new(
        batch_id: fact.target_stream.stream_id,
        page_start: 50,
        page_end: 50
      )
    )
    expect(fact.event.to_h).not_to have_key(:source_event)
    expect(fact.event.to_h).not_to have_key(:requested_at)
  end

  it "maps a requested cancellation and its terminal fact without retaining counters" do
    items = build_source_items(1)
    persist_source_skills(items)
    creation_event = persist_batch(legacy_creation(items:), actor:)
    request = Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchCancellationRequestedV1.new(
      batch_id: source_batch_id,
      requester: Coordinator::Write::OperationBatches::ActorV1.new(kind: actor.kind, id: actor.id),
      requested_at: timestamp(1)
    )
    request_event = persist_batch(request, actor:, caused_by: creation_event)
    cancelled = Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchCancelledV1.new(
      batch_id: source_batch_id,
      succeeded: 0,
      rejected: 0,
      not_run: 1,
      cancellation_event: event_reference(request_event),
      cancelled_at: timestamp(2)
    )
    cancelled_event = persist_batch(cancelled, actor: system_actor, caused_by: request_event)
    upper_position = cancelled_event.global_position

    [ creation_event, request_event, cancelled_event ].each do |event|
      expect(plan(event, upper_position:)).to be_success
      expect(dispatch(event, upper_position:)).to be_success
    end
    target_batch_id = transform(creation_event, upper_position:).value!.first.target_stream.stream_id
    request_fact = transform(request_event, upper_position:).value!.sole
    cancelled_fact = transform(cancelled_event, upper_position:).value!.sole

    expect(request_fact.event).to eq(
      Coordinator::Write::Events::OperationBatchCancellationRequestedV2.new(batch_id: target_batch_id)
    )
    expect(cancelled_fact.event).to eq(
      Coordinator::Write::Events::OperationBatchCancelledV2.new(batch_id: target_batch_id)
    )
    expect(cancelled_fact.event.to_h.keys).to contain_exactly(:batch_id)
    expect(
      Coordinator::Write::OperationBatches::Loader.new(event_store: target_store).call(target_batch_id).state
    ).to have_attributes(running?: false, succeeded_count: 0, rejected_count: 0)
  end

  private

  def persist_completed_batch
    persist_source_skills(source_items)
    creation_event = persist_batch(legacy_creation, actor:)
    command_completion = legacy_command_completion(creation_event)
    completion_event = persist_command(command_completion)
    success = success_outcome(command_completion, completion_event:)
    success_event = persist_batch(success, actor: system_actor, index: 0, caused_by: completion_event)
    rejection_event = persist_batch(rejection_outcome, actor: system_actor, index: 1, caused_by: creation_event)
    completed_event = persist_batch(
      completed_outcome(success, rejection_outcome),
      actor: system_actor,
      caused_by: rejection_event
    )
    [ creation_event, completion_event, success_event, rejection_event, completed_event ]
  end

  def legacy_creation(items: source_items)
    Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchCreatedV1.new(
      batch_id: source_batch_id,
      target_tool: "skill_publish",
      total: items.length,
      page_size: Coordinator::Shared::Types::OPERATION_BATCH_PAGE_SIZE,
      items:,
      manifest_digest: manifest_builder.digest(items),
      encoded_byte_size: manifest_builder.encoded_byte_size(
        command_id: batch_command_id,
        actor:,
        batch_id: source_batch_id,
        target_tool: "skill_publish",
        items:
      ),
      requester: Coordinator::Write::OperationBatches::ActorV1.new(kind: actor.kind, id: actor.id),
      created_at: timestamp(0)
    )
  end

  def legacy_command_completion(creation_event)
    item = source_items.fetch(0)
    publication = event_reference(creation_event)
    Coordinator::Write::HistoryMigrations::LegacyEvents::CommandCompletedV1.new(
      command_id: item.command_input.command_id,
      tool_name: item.command_input.tool_name,
      canonical_input_digest: item.canonical_input_digest,
      status: "ok",
      summary: "Skill revision published.",
      receipt: item.command_input.command_id,
      data: Coordinator::Write::CommandReceiptData::SkillPublication.new(
        skill_id: item.command_input.input.skill_id,
        name: item.command_input.input.name,
        scope: item.command_input.input.scope,
        revision: 1,
        content_digest: item.command_input.input.content_digest,
        asset_count: item.command_input.input.assets.length,
        publication_event: publication,
        published_at: timestamp(1)
      ),
      warnings: [],
      next_actions: [],
      emitted_events: [],
      completed_at: timestamp(1)
    )
  end

  def success_outcome(command_completion, completion_event:)
    item = source_items.fetch(0)
    Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchItemSucceededV1.new(
      batch_id: source_batch_id,
      index: item.index,
      command_id: item.command_input.command_id,
      canonical_input_digest: item.canonical_input_digest,
      target_completion: event_reference(completion_event),
      result: Coordinator::Write::Tasks::StructuredContentV1.new(
        status: "ok",
        summary: command_completion.summary,
        command_id: command_completion.command_id,
        receipt: command_completion.receipt,
        context_token: nil,
        data: command_completion.data,
        warnings: command_completion.warnings,
        next_actions: command_completion.next_actions
      ),
      finished_at: timestamp(2)
    )
  end

  def rejection_outcome(item: source_items.fetch(1))
    error = Coordinator::Write::Tasks::DomainErrorV1::SkillRevisionConflictError.new(
      code: "skill_revision_conflict",
      message: "Skill revision changed",
      details: Coordinator::Write::Tasks::DomainErrorV1::SkillRevisionDetails.new(
        skill_id: item.command_input.input.skill_id,
        name: item.command_input.input.name,
        scope: item.command_input.input.scope,
        expected_revision: item.command_input.input.expected_revision,
        current_revision: 1
      )
    )
    Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchItemRejectedV1.new(
      batch_id: source_batch_id,
      index: item.index,
      command_id: item.command_input.command_id,
      canonical_input_digest: item.canonical_input_digest,
      result: Coordinator::Write::Tasks::StructuredContentV1.new(
        status: "conflict",
        summary: error.message,
        command_id: item.command_input.command_id,
        receipt: nil,
        context_token: nil,
        data: error,
        warnings: [],
        next_actions: []
      ),
      finished_at: timestamp(3)
    )
  end

  def completed_outcome(*outcomes)
    document = outcomes.sort_by(&:index).map do |outcome|
      {
        index: outcome.index,
        command_id: outcome.command_id,
        canonical_input_digest: outcome.canonical_input_digest,
        status: outcome.is_a?(
          Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchItemSucceededV1
        ) ? "succeeded" : "rejected"
      }
    end
    Coordinator::Write::HistoryMigrations::LegacyEvents::OperationBatchCompletedV1.new(
      batch_id: source_batch_id,
      succeeded: 1,
      rejected: 1,
      outcome_manifest_digest: canonical_json.sha256(document),
      completed_at: timestamp(4)
    )
  end

  def skill_input(command_id:, name:)
    {
      command_id:,
      actor: { kind: actor.kind, id: actor.id },
      name:,
      scope: "project:operation-batch-migration",
      expected_revision: 0,
      description: "Migrate #{name}",
      instructions: "Preserve the modeled facts.",
      assets: []
    }
  end

  def persist_source_skills(items)
    items.each do |item|
      input = item.command_input.input
      payload = Coordinator::Write::Events::SkillRevisionPublishedV2.new(
        skill_id: input.skill_id,
        name: input.name,
        scope: input.scope,
        revision: 1,
        description: input.description,
        instructions: input.instructions,
        assets: [],
        content_digest: input.content_digest,
        published_at: timestamp(0)
      )
      persist(
        payload,
        stream: Coordinator::Write::StreamReference.new(
          context: "AgentKnowledge",
          stream_name: "Skill",
          stream_id: input.skill_id
        ),
        markers: [ "skill:#{input.skill_id}" ],
        actor:
      )
    end
  end

  def persist_batch(payload, actor:, index: nil, caused_by: nil)
    markers = [ "operation-batch:#{source_batch_id}" ]
    markers << "batch-item:#{source_batch_id}:#{index}" unless index.nil?
    persist(payload, stream: source_stream, markers:, actor:, caused_by:)
  end

  def persist_command(payload)
    persist(
      payload,
      stream: Coordinator::Write::StreamReference.new(
        context: "CoordinatorControl",
        stream_name: "Command",
        stream_id: payload.command_id
      ),
      markers: [ "command:#{payload.command_id}" ],
      actor:
    )
  end

  def persist(payload, stream:, markers:, actor:, caused_by: nil)
    source_store.append(
      stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => batch_command_id,
            "actor_kind" => actor.kind,
            "actor_id" => actor.id,
            "recorded_by" => "coordinator",
            "policy_version" => "operation-batch/v1"
          },
          markers:,
          caused_by:,
          correlation_id: source_correlation_id
        )
      ]
    ).sole
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def dispatch(source_event, upper_position:)
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def target_command_terminals(items)
    items.map do |item|
      target_store.read(
        Coordinator::Write::StreamFactory.new.command(item.command_id),
        Coordinator::Write::EventQueries::COMMAND_HISTORY
      ).last
    end
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def system_actor
    Coordinator::Write::Commands::Actor.new(kind: "system", id: "operation-batch-runner")
  end

  def timestamp(offset)
    format("2026-08-01T10:%02d:00.000000Z", offset)
  end

  def digest(label)
    canonical_json.sha256(label:)
  end
end
