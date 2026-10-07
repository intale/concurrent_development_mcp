# frozen_string_literal: true

RSpec.describe Coordinator::Read::CoordContexts::WorkIntentionSetLoader, :event_store do
  subject(:loader) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:factory) { Coordinator::Write::EventFactory.new }
  let(:intention_id) { SecureRandom.uuid_v7 }
  let(:set_id) { SecureRandom.uuid_v7 }
  let(:resource_id) { SecureRandom.uuid_v7 }
  let(:scope) do
    { repository_id: SecureRandom.uuid_v7, change_set_id: SecureRandom.uuid_v7,
     work_item_id: SecureRandom.uuid_v7, attempt_id: SecureRandom.uuid_v7 }
  end
  let(:metadata) do
    Coordinator::Write::EventMetadata.new(command_id: SecureRandom.uuid_v7,
      actor_kind: "agent", actor_id: "codex", recorded_by: "coordinator", policy_version: "coordinator-work-intention/v1")
  end
  let(:declaration) do
    Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
      **scope, intention_id:, set_id:, resource_id:, agent_id: "codex", mode: "shared",
      purpose: "Improve the same file", context: "Repeated renewal replay", object_format: "sha1",
      base_commit_oid: "a" * 40, base_blob_oid: nil, fencing_token: 1, expires_at: "2026-12-01T00:00:00.000000Z"
    )
  end

  before do
    append(streams.resource(resource_id), Coordinator::Write::Events::ResourceIdentityV2::Registered.new(
      resource_id:, repository_id: scope.fetch(:repository_id), kind: "file", normalized_path: "README.md"
    ))
    append(streams.work_intention_set(set_id),
      Coordinator::Write::Events::WorkIntentionSetCreatedV1.new(**scope, set_id:),
      Coordinator::Write::Events::WorkIntentionAddedToSetV1.new(set_id:, intention_id:, resource_id:))
    append(streams.resource_work_intention(intention_id), declaration)
  end

  it "accepts replay of an earlier renewal after another renewal and withdrawal exist" do
    first = append(streams.resource_work_intention(intention_id), renewal("01")).sole
    last = append(streams.resource_work_intention(intention_id), renewal("02")).sole
    withdrawn = append(streams.resource_work_intention(intention_id),
      Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1.new(intention_id:, resource_id:, fencing_token: 1, reason: nil)).sole

    2.times do
      view = loader.call(first, renewal("01"))
      expect(view).to have_attributes(set_id:, last_renewed_event: last, release_event: withdrawn,
        expires_at: "2026-12-01T02:00:00.000000Z")
    end
  end

  it "rejects a trigger that belongs to another persisted intention stream" do
    other = append(streams.resource_work_intention(SecureRandom.uuid_v7), renewal("01")).sole

    expect { loader.call(other, renewal("01")) }
      .to raise_error(Coordinator::Read::InvalidProjectionSource, "Work-intention trigger is absent from its source stream")
  end

  private

  def renewal(hour)
    Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
      intention_id:, resource_id:, fencing_token: 1, expires_at: "2026-12-01T#{hour}:00:00.000000Z")
  end

  def append(stream, *facts)
    events = facts.map do |fact|
      factory.build!(event: fact, event_id: SecureRandom.uuid_v7, metadata:, markers: [], correlation_id: SecureRandom.uuid_v7)
    end
    event_store.append(stream, events)
  end
end
