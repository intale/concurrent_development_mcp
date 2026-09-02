# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ReadinessCommandBuilder do
  subject(:builder) { described_class.new }

  let(:source_reference) do
    Coordinator::Write::EventReference.new(
      event_id: "0198c000-0000-7000-8000-000000000001",
      type: "ChangeSetActivated",
      stream_context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      stream_id: "CS-100",
      stream_revision: 4
    )
  end
  let(:source_payload) do
    Coordinator::Write::Events::ChangeSetActivatedV1.new(
      change_set_id: "CS-100",
      work_item_count: 1,
      dependency_count: 0,
      activated_at: "2026-08-20T14:15:00.000000Z"
    )
  end
  let(:source) do
    Coordinator::Processes::ChangeSetActivationSource.new(
      event: PgEventstore::Event.new(id: source_reference.event_id, type: "ChangeSetActivated"),
      reference: source_reference,
      payload: source_payload
    )
  end

  it "uses the persisted process-step command ID and a readable compound marker" do
    command_id = "0198c000-0000-7000-8000-000000000002"
    command = builder.call(source:, work_item_id: "W-200", command_id:)

    expect(command.command_id).to eq(command_id)
    expect(command.readiness_decision_id).to eq(command_id)
    expect(command.actor.to_h).to eq(kind: "system", id: "change-set-readiness")
    expect(command.source_activation_event_id).to eq(source_reference.event_id)
    expect(command.source_activation_revision).to eq(4)
    expect(command.process_decision_components).to contain_exactly(
      "process-manager:change-set-readiness",
      "policy-version:change-set-readiness/v1",
      "source-event-id:0198c000-0000-7000-8000-000000000001",
      "source-stream-context:DevelopmentPlanning",
      "source-stream-name:ChangeSet",
      "source-stream-id:CS-100",
      "source-stream-revision:4",
      "target-work-item:W-200",
      "process-step:evaluate-work-item-readiness"
    )
    expect(command.process_decision_marker).to start_with("compound:process-decision:v2|")
    expect(command.process_decision_marker).not_to match(/sha|md5/i)
  end

  it "is stable when the persisted process-step identity is replayed" do
    command_id = "0198c000-0000-7000-8000-000000000003"
    first = builder.call(source:, work_item_id: "W-200", command_id:)
    redelivery = builder.call(source:, work_item_id: "W-200", command_id:)

    expect(redelivery).to eq(first)
  end
end
