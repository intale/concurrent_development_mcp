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
      payload: Coordinator::Write::Events::ChangeSetActivatedV2.new(
        change_set_id: "CS-100"
      )
    )
  end
  let(:memberships) do
    %w[W-100 W-200].map do |work_item_id|
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(
        change_set_id: "CS-100",
        work_item_id:
      )
    end
  end

  it "accepts the complete bounded authoritative target set" do
    expect(builder.call(source:, memberships:).work_item_ids).to eq(%w[W-100 W-200])
  end

  it "rejects empty or duplicate authoritative memberships through the dry contract" do
    expect { builder.call(source:, memberships: []) }
      .to raise_error(Coordinator::Processes::InvalidReadinessTargets, /work_item_ids/)
    expect { builder.call(source:, memberships: [ memberships.first, memberships.first ]) }
      .to raise_error(Coordinator::Processes::InvalidReadinessTargets, /unique authoritative memberships/)
  end
  it "rejects a membership from another ChangeSet" do
    foreign = Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(
      change_set_id: "CS-OTHER", work_item_id: "W-300"
    )

    expect { builder.call(source:, memberships: [ foreign ]) }
      .to raise_error(Coordinator::Processes::InvalidReadinessTargets, /activated ChangeSet/)
  end

  it "rejects more than the bounded authoritative membership limit" do
    oversized = Array.new(101) do |index|
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(
        change_set_id: "CS-100", work_item_id: "W-#{index}"
      )
    end

    expect { builder.call(source:, memberships: oversized) }
      .to raise_error(Coordinator::Processes::InvalidReadinessTargets, /work_item_ids/)
  end
end
