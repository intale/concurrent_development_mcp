# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CandidateGet, :read_model do
  subject(:query) { described_class.new }

  it "returns not-observed and partial available views without a freshness gate" do
    absent = query.call(candidate_id: "CAN-candidate-get").value!
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "candidate_not_observed")

    create(
      :coordinator_read_candidate,
      candidate_id: "CAN-candidate-get",
      build_context_digest: "sha256:#{'b' * 64}"
    )
    partial = query.call(candidate_id: "CAN-candidate-get").value!

    expect(partial).to have_attributes(status: "ok")
    expect(partial.data.candidate).to have_attributes(manifest: nil, build_context: nil)
    expect(partial.warnings).to contain_exactly(
      "The Candidate manifest has not yet been observed by this projection.",
      "The Candidate build context has not yet been observed by this projection."
    )
  end

  it "returns a complete available view when both evidence projections exist" do
    create(
      :coordinator_read_candidate,
      :manifest_observed,
      :build_context_observed,
      candidate_id: "CAN-candidate-complete"
    )

    complete = query.call(candidate_id: "CAN-candidate-complete").value!

    expect(complete.data.candidate).to have_attributes(
      manifest: be_a(Coordinator::Read::CandidateManifestViewV1),
      build_context: be_a(Coordinator::Read::CandidateBuildContextViewV1)
    )
    expect(complete.warnings).to be_empty
  end

  it "returns typed invalid input" do
    result = query.call(candidate_id: "bad id").value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end
end
