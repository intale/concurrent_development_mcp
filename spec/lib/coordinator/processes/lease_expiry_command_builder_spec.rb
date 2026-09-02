# frozen_string_literal: true

RSpec.describe Coordinator::Processes::LeaseExpiryCommandBuilder do
  it "builds the system command with the persisted process-step command identity" do
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

    command_id = "06919191-9192-7191-8191-919191919191"
    command = described_class.new.call(source, command_id:)

    expect(command).to have_attributes(
      command_id:,
      actor: have_attributes(kind: "system", id: "lease-expiry-policy-v1"),
      resource_id: payload.resource_id,
      lease_id: payload.lease_id,
      lease_set_id: payload.lease_set_id,
      fencing_token: payload.fencing_token,
      expected_expires_at: payload.expires_at
    )
    expect(described_class.new.call(source, command_id:)).to eq(command)
  end
end
