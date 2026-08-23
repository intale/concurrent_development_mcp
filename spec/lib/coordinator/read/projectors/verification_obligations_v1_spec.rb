# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::VerificationObligationsV1,
               :event_store,
               :read_model do
  let(:projector) { described_class.new }
  let(:repository) { Coordinator::Read::Repositories::VerificationObligations.new }

  it "projects complete creation evidence idempotently and rebuilds without write-side effects" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-projection")
    event = created.fetch(:event)
    payload = created.fetch(:payload)

    projector.call(event)
    projector.call(event)

    first = page(change_set_id: created.dig(:pair, :ids, :change_set_id)).items.sole
    expect(Coordinator::Read::VerificationObligation.count).to eq(1)
    expect(first).to have_attributes(
      obligation_id: payload.obligation_id,
      kind: "candidate_compatibility",
      status: "open",
      enforcement: "merge_gate",
      source_candidate: payload.source_candidate,
      target_candidate: payload.target_candidate,
      reasons: payload.reasons,
      required_evidence: payload.required_evidence,
      policy: payload.policy,
      validity_input_digest: payload.validity_input_digest
    )
    expect(first.evidence).to have_attributes(
      event: CandidateObligationScenario.reference(event),
      actor: have_attributes(
        kind: "system",
        id: "candidate-impact-obligation-policy",
        authenticated: false
      ),
      markers: event.markers,
      metadata: event.metadata,
      global_position: event.global_position,
      causation_id: event.causation_id,
      correlation_id: event.correlation_id
    )

    original = first.to_h
    Coordinator::Read::VerificationObligation.delete_all
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "verification_obligations",
      projection_version: 1
    ).delete_all
    projector.call(event)

    expect(page(change_set_id: payload.change_set_id).items.sole.to_h).to eq(original)
    expect(CandidateObligationScenario.obligation_events(payload.obligation_id)).to contain_exactly(event)
  end

  private

  def page(change_set_id:)
    repository.page(
      Coordinator::Read::VerificationObligationListQueryV1.new(
        change_set_id:,
        candidate_id: nil,
        work_item_id: nil,
        repository_id: nil,
        kind: nil,
        enforcement: nil,
        status: "open",
        after_global_position: nil,
        limit: 20
      )
    )
  end
end
