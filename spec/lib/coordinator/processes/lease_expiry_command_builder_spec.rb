# frozen_string_literal: true

RSpec.describe Coordinator::Processes::LeaseExpiryCommandBuilder do
  it "builds the system command with the persisted process-step command identity" do
    payload = Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
      intention_id: "04919191-9191-7191-8191-919191919191",
      set_id: "03919191-9191-7191-8191-919191919191",
      resource_id: "01919191-9191-7191-8191-919191919191",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      agent_id: "agent-a",
      mode: "exclusive",
      purpose: "Protect app/models/a.rb while it is rewritten",
      context: "The model shape is changing",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid: "b" * 40,
      fencing_token: 1,
      expires_at: "2026-08-22T10:15:00.000000Z"
    )
    event = PgEventstore::Event.new(
      id: "06919191-9191-7191-8191-919191919191",
      type: "ResourceWorkIntentionDeclared"
    )
    source = Coordinator::Processes::LeaseExpirySource.new(
      event:,
      reference: Coordinator::Write::EventReference.new(
        event_id: event.id,
        type: event.type,
        stream_context: "DevelopmentCoordination",
        stream_name: "ResourceWorkIntention",
        stream_id: payload.intention_id,
        stream_revision: 0
      ),
      payload:,
      state: Coordinator::Write::Domain::WorkIntentions::State.reduce([ payload ])
    )

    command_id = "06919191-9192-7191-8191-919191919191"
    command = described_class.new.call(source, command_id:)

    expect(command).to have_attributes(
      command_id:,
      actor: have_attributes(kind: "system", id: "lease-expiry-policy-v1"),
      resource_id: payload.resource_id,
      lease_id: payload.intention_id,
      lease_set_id: payload.set_id,
      fencing_token: payload.fencing_token,
      expected_expires_at: payload.expires_at
    )
    expect(described_class.new.call(source, command_id:)).to eq(command)
  end
end
