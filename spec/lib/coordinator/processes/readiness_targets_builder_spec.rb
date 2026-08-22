# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ReadinessTargetsBuilder do
  subject(:builder) { described_class.new }

  let(:source) do
    reference = Coordinator::Write::EventReference.new(
      event_id: "0198c000-0000-7000-8000-000000000001",
      type: "ChangeSetActivated",
      stream_context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      stream_id: "CS-100",
      stream_revision: 4
    )
    Coordinator::Processes::ChangeSetActivationSource.new(
      event: PgEventstore::Event.new(id: reference.event_id, type: "ChangeSetActivated"),
      reference:,
      payload: Coordinator::Write::Events::ChangeSetActivatedV1.new(
        change_set_id: "CS-100",
        work_item_count: 2,
        dependency_count: 0,
        activated_at: "2026-08-20T14:15:00.000000Z"
      ),
      correlation_id: "cmd-250"
    )
  end
  let(:memberships) do
    %w[W-100 W-200].map do |work_item_id|
      Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
        change_set_id: "CS-100",
        work_item_id:,
        added_at: "2026-08-20T14:12:00.000000Z"
      )
    end
  end

  it "accepts the complete bounded authoritative target set" do
    expect(builder.call(source:, memberships:).work_item_ids).to eq(%w[W-100 W-200])
  end

  it "rejects missing or duplicate membership facts through the dry contract" do
    expect { builder.call(source:, memberships: memberships.first(1)) }
      .to raise_error(Coordinator::Processes::InvalidReadinessTargets, /source activation work-item count/)
    expect { builder.call(source:, memberships: [ memberships.first, memberships.first ]) }
      .to raise_error(Coordinator::Processes::InvalidReadinessTargets, /unique authoritative memberships/)
  end
end
