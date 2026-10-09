# frozen_string_literal: true

RSpec.describe Coordinator::Processes::WorkIntentionExpirySourceBuilder, :event_store do
  subject(:builder) { described_class.new }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:intention_id) { SecureRandom.uuid_v7 }
  let(:resource_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:set_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:stream) { Coordinator::Write::StreamFactory.new.resource_work_intention(intention_id) }
  let(:payload) do
    Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
      intention_id:, resource_id:, repository_id:, set_id:,
      change_set_id: SecureRandom.uuid_v7, work_item_id: SecureRandom.uuid_v7,
      attempt_id: SecureRandom.uuid_v7, agent_id: "source-agent",
      mode: "shared", purpose: "Edit independently", context: nil,
      object_format: "sha1", base_commit_oid: "a" * 40, base_blob_oid: nil,
      fencing_token: 1, expires_at: "2026-08-30T11:00:00.000000Z"
    )
  end

  it "accepts a current-schema declaration without treating its originating policy as today's policy" do
    source = persist(payload)

    expect(builder.call(source)).to have_attributes(event: source, payload:)
    expect(source.metadata.fetch("policy_version")).to eq("coordinator-resource-lease/v2")
    expect(source.correlation_id).to eq(correlation_id)
    expect(event_store.read_at(stream, 1)).to be_nil
  end

  it "accepts the same provenance on a renewal and preserves its exact source locator" do
    renewal = Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
      intention_id:, resource_id:, fencing_token: 1, expires_at: "2026-08-30T12:00:00.000000Z"
    )
    persist(payload)
    source = persist(renewal)
    locator = Coordinator::Processes::WorkIntentionExpirySourceLocatorV1.from_source(builder.call(source))

    expect(locator).to have_attributes(
      source_event_id: source.id, resource_stream_id: intention_id, stream_revision: 1
    )
    expect(event_store.read_at(stream, 2)).to be_nil
  end

  it "still rejects a persisted source without command provenance" do
    source = persist(payload, omit_command: true)

    expect { builder.call(source) }.to raise_error(Coordinator::Processes::InvalidSourceEvent, /must carry command provenance/)
  end

  private

  def persist(event, omit_command: false)
    command_id = SecureRandom.uuid_v7
    metadata = Coordinator::Write::EventMetadata.new(
      command_id:, actor_kind: "agent", actor_id: "source-agent",
      recorded_by: "coordinator", policy_version: "coordinator-resource-lease/v2"
    )
    markers = [
      "command:#{command_id}", "work-intention:#{intention_id}",
      "resource:#{resource_id}", "work-intention-set:#{set_id}"
    ] + Coordinator::Write::RepositoryMarkerBuilder.new.work_intention_event_markers(
      repository_id:, resource_path: "config/routes.rb"
    )
    source = Coordinator::Write::EventFactory.new.build!(
      event:, event_id: SecureRandom.uuid_v7, metadata:, markers:, correlation_id:
    )
    source.metadata.delete("command_id") if omit_command
    event_store.append(stream, [ source ]).sole
  end
end
