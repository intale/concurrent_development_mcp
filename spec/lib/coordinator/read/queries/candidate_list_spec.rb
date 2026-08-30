# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CandidateList, :read_model do
  subject(:query) { described_class.new }

  it "pages Attempt checkpoints behind an opaque global-position cursor" do
    attempt_id = "A-candidate-list"
    %w[0 1 2].each_with_index do |suffix, index|
      create(
        :coordinator_read_candidate,
        :manifest_observed,
        candidate_id: "CAN-candidate-list-#{suffix}",
        attempt_id:,
        submitted_global_position: 100 + index,
        head_commit_oid: (index + 2).to_s * 40
      )
    end

    first = query.call(attempt_id:, limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true)
    expect(first.items.map(&:candidate_id)).to eq(%w[CAN-candidate-list-0 CAN-candidate-list-1])
    expect(first.next_global_position).to eq(first.items.last.submitted.global_position)

    second = query.call(
      attempt_id:,
      after_global_position: first.next_global_position,
      limit: 2
    ).value!.data.page
    expect(second).to have_attributes(has_more: false, next_global_position: nil)
    expect(second.items.map(&:candidate_id)).to eq([ "CAN-candidate-list-2" ])
    expect(second.items.sole).to have_attributes(
      manifest_observed: true,
      build_context_observed: false,
      evidence_status: "attributed_unverified"
    )
  end

  it "returns typed invalid input and permits an empty available page" do
    invalid = query.call(attempt_id: "bad id", limit: 101).value!
    empty = query.call(attempt_id: "A-unobserved").value!

    expect(invalid).to have_attributes(status: "invalid")
    expect(empty.data.page).to have_attributes(items: [], has_more: false)
  end
end
