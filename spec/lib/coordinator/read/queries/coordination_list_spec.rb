# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CoordinationList, :read_model do
  subject(:query) { described_class.new }

  COORDINATION_REPOSITORY_IDS = %w[
    018f0f4d-4e45-7abc-8def-000000000011
    018f0f4d-4e45-7abc-8def-000000000012
    018f0f4d-4e45-7abc-8def-000000000013
  ].freeze

  it "discovers bounded resumable coordination from exact projected Repository scope" do
    create_coordination(
      change_set_id: "CS-DISC-A",
      work_item_id: "W-DISC-A",
      attempt_id: "A-DISC-A",
      repository_id: COORDINATION_REPOSITORY_IDS.fetch(0),
      scope: "project:discovery",
      last_processed_at: Time.utc(2026, 8, 30, 12, 2),
      candidate_checkpoint_count: 1
    )
    create_coordination(
      change_set_id: "CS-DISC-B",
      work_item_id: "W-DISC-B",
      attempt_id: "A-DISC-B",
      repository_id: COORDINATION_REPOSITORY_IDS.fetch(1),
      scope: "project:discovery",
      last_processed_at: Time.utc(2026, 8, 30, 12, 1)
    )
    create_coordination(
      change_set_id: "CS-OTHER",
      work_item_id: "W-OTHER",
      attempt_id: "A-OTHER",
      repository_id: COORDINATION_REPOSITORY_IDS.fetch(2),
      scope: "project:other",
      last_processed_at: Time.utc(2026, 8, 30, 12)
    )

    first_page = query.call(scope: "project:discovery", statuses: [ "active" ], limit: 1).value!
    expect(first_page).to have_attributes(status: "ok")
    expect(first_page.warnings).to contain_exactly(match(/projection-derived/))
    expect(first_page.to_h.keys & %i[fresh pending projection_status stream_revision]).to be_empty
    expect(first_page.data.page).to have_attributes(has_more: true)
    expect(first_page.next_actions.map(&:tool)).to contain_exactly("coord_context", "coordination_list")

    second_page = query.call(
      scope: "project:discovery",
      statuses: [ "active" ],
      cursor: first_page.data.page.continuation_cursor.to_h,
      limit: 1
    ).value!
    discovered = [ *first_page.data.page.items, *second_page.data.page.items ]
    expect(discovered.map(&:change_set_id)).to contain_exactly("CS-DISC-A", "CS-DISC-B")
    checkpointed = discovered.find { _1.change_set_id == "CS-DISC-A" }
    expect(checkpointed).to have_attributes(
      repository_ids: [ COORDINATION_REPOSITORY_IDS.fetch(0) ],
      work_item_ids: [ "W-DISC-A" ],
      active_attempt_ids: [ "A-DISC-A" ],
      candidate_checkpoint_count: 1
    )
  end

  it "serves the latest available projected checkpoint count" do
    create_coordination(
      change_set_id: "CS-CHECKPOINT",
      work_item_id: "W-CHECKPOINT",
      attempt_id: "A-CHECKPOINT",
      repository_id: COORDINATION_REPOSITORY_IDS.fetch(0),
      scope: "project:checkpoint",
      candidate_checkpoint_count: 1
    )

    available = query.call(scope: "project:checkpoint").value!.data.page.items.sole

    expect(available).to have_attributes(
      change_set_id: "CS-CHECKPOINT",
      candidate_checkpoint_count: 1
    )
  end

  it "returns typed empty and invalid results without inferring a scope hierarchy" do
    empty = query.call(scope: "project:absent").value!
    invalid = query.call(
      scope: "project:absent",
      statuses: [ "active", "active" ],
      limit: 51
    ).value!

    expect(empty.data.page).to have_attributes(items: [], has_more: false)
    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
  end

  def create_coordination(
    change_set_id:,
    work_item_id:,
    attempt_id:,
    repository_id:,
    scope:,
    last_processed_at: Time.utc(2026, 8, 30, 12),
    candidate_checkpoint_count: 0
  )
    create(
      :coordinator_read_repository,
      repository_id:,
      repository_key: change_set_id.downcase,
      scope:
    )
    create(
      :coordinator_read_coord_context,
      change_set_id:,
      work_item_id:,
      attempt_id:,
      repository_id:,
      last_processed_at:,
      candidate_checkpoint_count:
    )
  end
end
