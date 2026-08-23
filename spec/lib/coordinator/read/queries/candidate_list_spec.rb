# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CandidateList, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:projector) { Coordinator::Read::Projectors::CandidatesV1.new }

  it "pages Attempt checkpoints with Kaminari behind an opaque global-position cursor" do
    prepared = CandidateScenario.prepare(prefix: "candidate-list")
    inputs = %w[b e f].each_with_index.map do |oid_character, index|
      prepared.fetch(:input).merge(
        command_id: "cmd-candidate-list-#{index}",
        candidate_id: "CAN-candidate-list-#{index}",
        head_commit_oid: oid_character * 40
      )
    end
    inputs.each do |input|
      CandidateScenario.execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
      CandidateScenario.candidate_events(input.fetch(:candidate_id)).each { projector.call(_1) }
    end
    attempt_id = prepared.dig(:ids, :attempt_id)

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
