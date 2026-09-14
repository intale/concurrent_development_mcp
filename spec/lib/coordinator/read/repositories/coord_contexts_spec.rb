# frozen_string_literal: true

RSpec.describe Coordinator::Read::Repositories::CoordContexts, :read_model do
  subject(:repository) { described_class.new }

  it "replaces earlier work-intention evidence with the latest observed set" do
    attempt_id = SecureRandom.uuid_v7
    change_set_id = SecureRandom.uuid_v7
    work_item_id = SecureRandom.uuid_v7
    repository_id = SecureRandom.uuid_v7
    set_id = SecureRandom.uuid_v7
    intention_id = SecureRandom.uuid_v7
    resource_id = SecureRandom.uuid_v7
    create(
      :coordinator_read_attempt_history,
      :with_write_set,
      attempt_id:,
      change_set_id:,
      work_item_id:,
      projection_version: Coordinator::Read::Projectors::CoordContextV1::PROJECTION.version
    )
    declaration = Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
      intention_id:,
      set_id:,
      resource_id:,
      repository_id:,
      change_set_id:,
      work_item_id:,
      attempt_id:,
      agent_id: "agent-rebuild",
      mode: "shared",
      purpose: "Continue the same Attempt after earlier coordination expired",
      context: "The latest available projection observes a replacement set.",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid: "b" * 40,
      fencing_token: 2,
      expires_at: "2026-09-11T13:00:00.000000Z"
    )
    event = ProjectionEventFactory.build(
      payload: declaration,
      stream: Coordinator::Write::StreamFactory.new.resource_work_intention(intention_id),
      stream_revision: 0,
      global_position: 1_000,
      policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      created_at: Time.utc(2026, 9, 11, 12)
    )
    view = Coordinator::Read::WorkIntentionSetViewV1.new(
      set_id:,
      change_set_id:,
      work_item_id:,
      attempt_id:,
      repository_id:,
      agent_id: "agent-rebuild",
      policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      intentions: [
        Coordinator::Read::WorkIntentionViewV1.new(
          intention_id:,
          resource_id:,
          resource_kind: "file",
          resource_path: "app/models/example.rb",
          base_blob_oid: "b" * 40,
          mode: "shared",
          purpose: "Continue the same Attempt after earlier coordination expired",
          context: "The latest available projection observes a replacement set.",
          fencing_token: 2
        )
      ],
      created_event: event,
      last_expanded_event: nil,
      last_renewed_event: nil,
      release_event: nil,
      declared_at: "2026-09-11T12:00:00.000000Z",
      last_expanded_at: nil,
      last_renewed_at: nil,
      previous_expires_at: nil,
      expires_at: "2026-09-11T13:00:00.000000Z",
      withdrawn_at: nil
    )

    repository.store_attempt_event(
      event:,
      payload: view,
      projection_version: Coordinator::Read::Projectors::CoordContextV1::PROJECTION.version
    )

    history = Coordinator::Read::AttemptHistory.find(attempt_id)
    expect(history).to have_attributes(
      write_set_lease_set_id: set_id,
      write_set_repository_id: repository_id,
      write_set_reserved_at_domain: Time.utc(2026, 9, 11, 12),
      write_set_expires_at_domain: Time.utc(2026, 9, 11, 13)
    )
    expect(history.write_set_resources.sole).to include(
      "intention_id" => intention_id,
      "resource_id" => resource_id,
      "resource_path" => "app/models/example.rb",
      "fencing_token" => 2
    )
  end
end
