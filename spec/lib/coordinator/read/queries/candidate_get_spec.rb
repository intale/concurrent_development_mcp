# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CandidateGet, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:projector) { Coordinator::Read::Projectors::CandidatesV1.new }

  it "returns not-observed, partial, and complete available views without a freshness gate" do
    events = CandidateScenario.submit(prefix: "candidate-get").fetch(:events)
    absent = query.call(candidate_id: "CAN-candidate-get").value!
    expect(absent).to have_attributes(status: "not_found")
    expect(absent.data).to have_attributes(code: "candidate_not_observed")

    projector.call(events.fetch(0))
    partial = query.call(candidate_id: "CAN-candidate-get").value!
    expect(partial).to have_attributes(status: "ok")
    expect(partial.data.candidate).to have_attributes(manifest: nil, build_context: nil)
    expect(partial.warnings).to contain_exactly(
      "The Candidate manifest has not yet been observed by this projection.",
      "The Candidate build context has not yet been observed by this projection."
    )

    events.drop(1).each { projector.call(_1) }
    complete = query.call(candidate_id: "CAN-candidate-get").value!
    expect(complete.data.candidate).to have_attributes(
      manifest: be_a(Coordinator::Read::CandidateManifestViewV1),
      build_context: be_a(Coordinator::Read::CandidateBuildContextViewV1)
    )
    expect(complete.warnings).to be_empty
  end

  it "returns typed invalid input without consulting pg_eventstore" do
    result = query.call(candidate_id: "bad id").value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end
end
