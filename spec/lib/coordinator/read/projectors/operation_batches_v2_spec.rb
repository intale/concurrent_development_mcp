# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::OperationBatchesV2, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::OperationBatches.new }
  let(:batch_id) { "018f0f4d-4e45-7abc-8def-000000000301" }
  let(:stream) { Coordinator::Write::StreamFactory.new.operation_batch(batch_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "converges idempotently under redelivery and serves the immutable manifest in bounded pages" do
    events = completed_events
    created = events.find { _1.type == "OperationBatchCreated" }

    events.each { projector.call(_1) }
    events.reverse_each { projector.call(_1) }

    first = fetch(limit: 1)
    expect(first).to have_attributes(
      status: "completed_with_errors",
      total: 2,
      succeeded: 1,
      rejected: 1,
      pending: 0,
      not_run: 0,
      has_more: true,
      next_after_index: 0
    )
    expect(first.items.sole).to have_attributes(index: 0, command_id: "item-1", status: "succeeded")
    expect(first.items.sole.arguments).to include(
      command_id: "item-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha"
    )

    second = fetch(after_index: first.next_after_index, limit: 1)
    expect(second).to have_attributes(has_more: false, next_after_index: nil)
    expect(second.items.sole).to have_attributes(index: 1, command_id: "item-2", status: "rejected")
    expect(first.created.correlation_id).to eq(created.correlation_id)
    expect(first.terminal.event.type).to eq("OperationBatchCompleted")
    expect(Coordinator::Read::OperationBatch.count).to eq(1)
    expect(Coordinator::Read::OperationBatchItem.count).to eq(2)
    expect(Coordinator::Read::OperationBatchOutcome.count).to eq(2)
    expect(processed_events.count).to eq(events.length)
  end

  it "exposes accepted cancellation before terminal completion and marks only terminal remainder not run" do
    manifest = manifest_events(skill_items)
    created = manifest.first
    cancellation = batch_event(
      Coordinator::Write::Events::OperationBatchCancellationRequestedV2.new(batch_id:),
      revision: manifest.length,
      position: 200,
      causation_id: created.id
    )

    manifest.each { projector.call(_1) }
    projector.call(cancellation)
    cancelling = fetch(limit: 100)
    expect(cancelling).to have_attributes(status: "cancelling", pending: 2, not_run: 0)
    expect(cancelling.items.map(&:status)).to eq(%w[pending pending])
    expect(cancelling.cancellation.event.type).to eq("OperationBatchCancellationRequested")
    expect(cancelling.terminal).to be_nil

    cancelled = batch_event(
      Coordinator::Write::Events::OperationBatchCancelledV2.new(batch_id:),
      revision: manifest.length + 1,
      position: 300,
      causation_id: cancellation.id
    )
    projector.call(cancelled)

    terminal = fetch(limit: 100)
    expect(terminal).to have_attributes(status: "cancelled", pending: 0, not_run: 2)
    expect(terminal.items.map(&:status)).to eq(%w[not_run not_run])
    expect(terminal.terminal.event.type).to eq("OperationBatchCancelled")
  end

  it "projects a Development Artifact relation batch using its current command envelope" do
    item = relation_item
    manifest_events([ item ], target_tool: "development_artifact_relation_declare").each do |event|
      projector.call(event)
    end

    batch = fetch(limit: 100)
    expect(batch).to have_attributes(
      target_tool: "development_artifact_relation_declare",
      status: "running",
      total: 1,
      pending: 1
    )
    expect(batch.items.sole.arguments).to include(
      command_id: "relation-item-1",
      source_artifact_id: "018f0f4d-4e45-7abc-8def-000000000201",
      relation: "references",
      target: { kind: "external", id: "https://example.test/reference" }
    )
  end

  def completed_events
    items = skill_items
    events = manifest_events(items)
    succeeded = batch_event(
      Coordinator::Write::Events::OperationBatchItemSucceededV2.new(
        batch_id:,
        index: 0,
        command_id: items.fetch(0).command_id
      ),
      revision: events.length,
      position: 200,
      causation_id: events.first.id
    )
    succeeded_link = completion_link_event(
      item: items.fetch(0),
      revision: events.length + 1,
      position: 250,
      causation_id: succeeded.id
    )
    rejected = batch_event(
      Coordinator::Write::Events::OperationBatchItemRejectedV2.new(
        batch_id:,
        index: 1,
        command_id: items.fetch(1).command_id,
        code: "skill_revision_conflict",
        reason: "Skill revision changed",
        retryable: false
      ),
      revision: events.length + 2,
      position: 300,
      causation_id: events.first.id
    )
    rejected_link = completion_link_event(
      item: items.fetch(1),
      revision: events.length + 3,
      position: 350,
      causation_id: rejected.id
    )
    completed = batch_event(
      Coordinator::Write::Events::OperationBatchCompletedV2.new(batch_id:),
      revision: events.length + 4,
      position: 400,
      causation_id: events.first.id
    )
    [ *events, succeeded, succeeded_link, rejected, rejected_link, completed ]
  end

  def skill_items
    @skill_items ||= [
      skill_item(command_id: "item-1", expected_revision: 0, digest_character: "a"),
      skill_item(command_id: "item-2", expected_revision: 0, digest_character: "b")
    ]
  end

  def skill_item(command_id:, expected_revision:, digest_character:)
    identity = Coordinator::Write::Skills::IdentityBuilder.new.call(
      name: "review",
      scope: "project:alpha"
    )
    target_command_id = SecureRandom.uuid_v7
    document = Coordinator::Write::CommandInputDocuments::PublishSkillRevisionV2.new(
      schema: "command-input/v2",
      command_id: target_command_id,
      tool_name: "skill_publish",
      input: {
        actor: { actor_kind: "agent", actor_id: "agent-1" },
        skill_id: identity.skill_id,
        name: identity.name,
        scope: identity.scope,
        expected_revision:,
        description: "Review a change",
        instructions: "Inspect the complete diff.",
        assets: [],
        content_digest: "sha256:#{digest_character * 64}"
      }
    )
    Coordinator::Write::OperationBatches::ItemV2.new(
      index: command_id == "item-1" ? 0 : 1,
      request_id: command_id,
      command_input: document,
      canonical_input_digest: "sha256:#{digest_character * 64}"
    )
  end

  def relation_item
    source_id = "018f0f4d-4e45-7abc-8def-000000000201"
    relation_id = "018f0f4d-4e45-7abc-8def-000000000202"
    document = Coordinator::Write::CommandInputDocuments::DeclareDevelopmentArtifactRelationV1.new(
      schema: "command-input/v1",
      command_id: SecureRandom.uuid_v7,
      tool_name: "development_artifact_relation_declare",
      input: {
        actor: { actor_kind: "agent", actor_id: "agent-1" },
        artifact_relation: {
          relation_id:,
          source_artifact_id: source_id,
          relation: "references",
          target: { kind: "external", id: "https://example.test/reference" },
          attributes: { path: nil, fragment: nil, normalized_locator: nil }
        },
        supersedes_relation_id: nil,
        supersession_reason: nil
      }
    )
    Coordinator::Write::OperationBatches::ItemV2.new(
      index: 0,
      request_id: "relation-item-1",
      command_input: document,
      canonical_input_digest: "sha256:#{'c' * 64}"
    )
  end

  def manifest_events(items, target_tool: "skill_publish")
    payloads = [
      Coordinator::Write::Events::OperationBatchCreatedV2.new(batch_id:),
      Coordinator::Write::Events::OperationBatchTargetSelectedV1.new(batch_id:, target_tool:),
      *items.map do |item|
        Coordinator::Write::Events::OperationBatchItemEnqueuedV1.new(
          batch_id:,
          index: item.index,
          command_id: item.command_id,
          input: item.submitted_input
        )
      end
    ]
    payloads.each_with_index.map do |payload, revision|
      batch_event(payload, revision:, position: 100 + revision)
    end
  end

  def completion_link_event(item:, revision:, position:, causation_id:)
    batch_event(
      Coordinator::Write::Events::OperationBatchItemCompletionLinkedV1.new(
        batch_id:,
        index: item.index,
        command_id: item.command_id,
        completion: Coordinator::Write::EventReference.new(
          event_id: SecureRandom.uuid_v7,
          type: "CommandSucceeded",
          stream_context: "CoordinatorControl",
          stream_name: "Command",
          stream_id: item.command_id,
          stream_revision: 1
        )
      ),
      revision:,
      position:,
      causation_id:
    )
  end

  def batch_event(payload, revision:, position:, causation_id: nil)
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      command_id: "cmd-batch-projector-#{revision}",
      policy_version: "operation-batch/v2",
      metadata: batch_metadata(payload, revision:),
      actor_id: "agent-1",
      correlation_id:,
      causation_id:,
      markers: [ "operation-batch:#{batch_id}" ]
    )
  end

  def batch_metadata(payload, revision:)
    common = {
      command_id: "cmd-batch-projector-#{revision}",
      actor_kind: "agent",
      actor_id: "agent-1",
      recorded_by: "coordinator",
      policy_version: "operation-batch/v2"
    }
    case payload
    when Coordinator::Write::Events::OperationBatchCreatedV2
      Coordinator::Write::Metadata::OperationBatchCreationV2.new(
        **common,
        manifest_digest: "sha256:#{'d' * 64}",
        page_size: Coordinator::Shared::Types::OPERATION_BATCH_PAGE_SIZE
      )
    when Coordinator::Write::Events::OperationBatchItemEnqueuedV1
      Coordinator::Write::Metadata::OperationBatchItemV1.new(
        **common,
        canonical_input_digest: "sha256:#{payload.index.zero? ? 'a' * 64 : 'b' * 64}",
        encoded_byte_size: 500
      )
    else
      Coordinator::Write::EventMetadata.new(common)
    end
  end

  def fetch(after_index: nil, limit:)
    repository.fetch(
      Coordinator::Read::OperationBatchGetQueryV1.new(batch_id:, after_index:, limit:)
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "operation_batches",
      projection_version: 2
    )
  end
end
