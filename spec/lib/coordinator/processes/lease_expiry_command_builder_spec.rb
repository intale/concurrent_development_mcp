# frozen_string_literal: true

RSpec.describe Coordinator::Processes::LeaseExpiryCommandBuilder do
  it "derives one deterministic system command from a schema-v2 parent event" do
    payload = ResourceLeaseExamples.acquisition
    event = PgEventstore::Event.new(
      id: "06919191-9191-7191-8191-919191919191",
      type: "ResourceLeaseAcquired"
    )
    source = Coordinator::Processes::LeaseExpirySource.new(
      event:,
      reference: Coordinator::Write::EventReference.new(
        event_id: event.id,
        type: event.type,
        stream_context: "DevelopmentCoordination",
        stream_name: "ResourceLease",
        stream_id: payload.resource_id,
        stream_revision: 0
      ),
      payload:
    )

    command = described_class.new.call(source)

    expect(command).to have_attributes(
      actor: have_attributes(kind: "system", id: "lease-expiry-policy-v1"),
      resource_id: payload.resource_id,
      lease_id: payload.lease_id,
      lease_set_id: payload.lease_set_id,
      fencing_token: payload.fencing_token,
      expected_expires_at: payload.expires_at
    )
    expect(command.command_id).to start_with("internal:lease-expiry:v1:")
    expect(described_class.new.call(source)).to eq(command)
  end
end
