# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::VerificationObligationsV1,
               :event_store,
               :read_model do
  let(:projector) { described_class.new }
  let(:repository) { Coordinator::Read::Repositories::VerificationObligations.new }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

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
    expect(first).to have_attributes(claim_state: "unclaimed", claim: nil)
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

  it "projects the latest fenced claim without changing the open obligation or its creation cursor" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-claim-projection")
    obligation_id = created.fetch(:result).obligation_id
    projector.call(created.fetch(:event))

    first_claim = claim(
      obligation_id:,
      command_id: "cmd-project-claim-blue",
      agent_id: "agent-blue",
      at: Time.utc(2026, 8, 24, 7, 0, 0)
    )
    projector.call(first_claim)
    projector.call(first_claim)

    active = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: "2026-08-24T07:04:59.999999Z"
    ).items.sole
    expect(active).to have_attributes(
      status: "open",
      claim_state: "active",
      claim: have_attributes(
        claim_id: first_claim.data.fetch("claim_id"),
        claimant_id: "agent-blue",
        fencing_token: 1,
        claimed_at: "2026-08-24T07:00:00.000000Z",
        expires_at: "2026-08-24T07:05:00.000000Z"
      )
    )
    expect(active.evidence.global_position).to eq(created.fetch(:event).global_position)
    expect(active.claim.evidence).to have_attributes(
      event: CandidateObligationScenario.reference(first_claim),
      actor: have_attributes(kind: "agent", id: "agent-blue", authenticated: false),
      markers: first_claim.markers,
      metadata: first_claim.metadata,
      global_position: first_claim.global_position,
      causation_id: first_claim.causation_id,
      correlation_id: first_claim.correlation_id
    )

    second_claim = claim(
      obligation_id:,
      command_id: "cmd-project-claim-green",
      agent_id: "agent-green",
      at: Time.utc(2026, 8, 24, 7, 5, 0)
    )
    projector.call(second_claim)

    reclaimed = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: "2026-08-24T07:05:00.000000Z"
    ).items.sole
    expect(reclaimed).to have_attributes(status: "open", claim_state: "active")
    expect(reclaimed.claim).to have_attributes(
      claim_id: second_claim.data.fetch("claim_id"),
      claimant_id: "agent-green",
      fencing_token: 2
    )
    expect(Coordinator::Read::VerificationObligation.count).to eq(1)
  end

  it "rolls back an out-of-order claim and accepts it after its creation fact" do
    created = CandidateObligationScenario.create_obligation(prefix: "obligation-claim-order")
    obligation_id = created.fetch(:result).obligation_id
    claim_event = claim(
      obligation_id:,
      command_id: "cmd-project-claim-order",
      agent_id: "agent-blue",
      at: Time.utc(2026, 8, 24, 7, 0, 0)
    )

    expect { projector.call(claim_event) }
      .to raise_error(
        Coordinator::Read::InvalidProjectionSource,
        /cannot precede VerificationObligationCreated/
      )
    expect(Coordinator::Read::ProcessedProjectionEvent.where(event_id: claim_event.id)).not_to exist

    projector.call(created.fetch(:event))
    projector.call(claim_event)

    projected = page(
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      observed_at: "2026-08-24T07:00:01.000000Z"
    ).items.sole
    expect(projected.claim).to have_attributes(claimant_id: "agent-blue", fencing_token: 1)
  end

  private

  def page(change_set_id:, observed_at: "2026-08-24T07:00:00.000000Z")
    repository.page(
      Coordinator::Read::VerificationObligationListQueryV1.new(
        obligation_id: nil,
        change_set_id:,
        candidate_id: nil,
        work_item_id: nil,
        repository_id: nil,
        kind: nil,
        enforcement: nil,
        status: "open",
        claimant_id: nil,
        claim_state: nil,
        after_global_position: nil,
        limit: 20,
        observed_at:
      )
    )
  end

  def claim(obligation_id:, command_id:, agent_id:, at:)
    Timecop.freeze(at) do
      Coordinator::Write::Operations::ExecuteClaimVerificationObligation.new(event_store:).call(
        command_id:,
        actor: { kind: "agent", id: agent_id },
        obligation_id:,
        claim_duration_seconds: 300
      ).value!
    end
    claim_events(obligation_id).last
  end

  def claim_events(obligation_id)
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationClaimed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end
end
