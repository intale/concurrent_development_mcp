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

  it "derives the deterministic internal command and compound marker from the complete tuple" do
    command = builder.call(source:, work_item_id: "W-200")

    expect(command.command_id).to match(/\Ainternal:readiness-v1:[0-9a-f]{64}\z/)
    expect(Coordinator::Shared::Types::InternalCommandId[command.command_id]).to eq(command.command_id)
    expect(command.readiness_decision_id).to eq(command.command_id)
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
    expect(command.process_decision_marker).to eq(
      "compound:process-decision:v1:sha256:#{command.command_id.delete_prefix("internal:readiness-v1:")}"
    )
  end

  it "is stable for redelivery and distinct for another target" do
    first = builder.call(source:, work_item_id: "W-200")
    redelivery = builder.call(source:, work_item_id: "W-200")
    another_target = builder.call(source:, work_item_id: "W-201")

    expect(redelivery).to eq(first)
    expect(another_target.command_id).not_to eq(first.command_id)
  end
end
