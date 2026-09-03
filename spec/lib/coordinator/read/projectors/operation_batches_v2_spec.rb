# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::OperationBatchesV2, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::OperationBatches.new }
  let(:batch_id) { "018f0f4d-4e45-7abc-8def-000000000301" }
  let(:stream) { Coordinator::Write::StreamFactory.new.operation_batch(batch_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "converges idempotently under reversed delivery and serves the immutable manifest in bounded pages" do
    created, succeeded, rejected, completed = completed_events
    events = [ created, succeeded, rejected, completed ]

    events.reverse_each { projector.call(_1) }
    events.each { projector.call(_1) }

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
    created = batch_event(created_payload(skill_items), revision: 0, position: 100)
    cancellation = batch_event(
      Coordinator::Write::Events::OperationBatchCancellationRequestedV2.new(batch_id:),
      revision: 1,
      position: 200,
      causation_id: created.id
    )

    projector.call(created)
    projector.call(cancellation)
    cancelling = fetch(limit: 100)
    expect(cancelling).to have_attributes(status: "cancelling", pending: 2, not_run: 0)
    expect(cancelling.items.map(&:status)).to eq(%w[pending pending])
    expect(cancelling.cancellation.event.type).to eq("OperationBatchCancellationRequested")
    expect(cancelling.terminal).to be_nil

    cancelled = batch_event(
      Coordinator::Write::Events::OperationBatchCancelledV2.new(batch_id:),
      revision: 2,
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
    event = batch_event(
      created_payload([ item ], target_tool: "development_artifact_relation_declare"),
      revision: 0,
      position: 100
    )

    projector.call(event)

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
    created = batch_event(created_payload(items), revision: 0, position: 100)
    succeeded = batch_event(
      Coordinator::Write::Events::OperationBatchItemSucceededV2.new(
        batch_id:,
        index: 0,
        command_id: items.fetch(0).command_id
      ),
      revision: 1,
      position: 200,
      causation_id: created.id
    )
    rejected = batch_event(
      Coordinator::Write::Events::OperationBatchItemRejectedV2.new(
        batch_id:,
        index: 1,
        command_id: items.fetch(1).command_id
      ),
      revision: 2,
      position: 300,
      causation_id: created.id
    )
    completed = batch_event(
      Coordinator::Write::Events::OperationBatchCompletedV2.new(batch_id:),
      revision: 3,
      position: 400,
      causation_id: created.id
    )
    [ created, succeeded, rejected, completed ]
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

  def created_payload(items, target_tool: "skill_publish")
    Coordinator::Write::Events::OperationBatchCreatedV2.new(
      batch_id:,
      target_tool:,
      page_size: Coordinator::Shared::Types::OPERATION_BATCH_PAGE_SIZE,
      items:
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
    return Coordinator::Write::EventMetadata.new(common) unless payload.is_a?(
      Coordinator::Write::Events::OperationBatchCreatedV2
    )

    Coordinator::Write::Metadata::OperationBatchCreationV2.new(
      **common,
      canonical_input_digest: "sha256:#{'c' * 64}",
      manifest_digest: "sha256:#{'d' * 64}",
      encoded_byte_size: 1_000
    )
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
