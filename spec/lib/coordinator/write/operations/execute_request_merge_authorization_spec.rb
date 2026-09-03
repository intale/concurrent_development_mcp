# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRequestMergeAuthorization, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:registry) { Coordinator::Write::EventSchemaRegistry.new }

  it "grants exact verified evidence without a Candidate policy and permits a later reevaluation" do
    registration = MergeSnapshotScenario.register(prefix: "auth-grant")
    verification = MergeSnapshotScenario.verify(registration, prefix: "auth-grant")
    input = MergeSnapshotScenario.authorization_input(registration, verification, prefix: "auth-grant")

    first = operation.call(input).value!
    reevaluation = operation.call(input).value!
    event = authorization_events(first.data.authorization_id).sole
    payload = load(event)

    expect(reevaluation.data.outcome).to eq("granted")
    expect(reevaluation.data.authorization_id).not_to eq(first.data.authorization_id)
    expect(authorization_events(reevaluation.data.authorization_id).length).to eq(1)
    expect(first.data.outcome).to eq("granted")
    expect(payload).to be_a(Coordinator::Write::Events::MergeAuthorizationGrantedV1)
    expect(payload.evaluation).to be_granted
    expect(payload.evaluation.current_policy.status).to eq("absent")
    expect(payload.evaluation.obligations).to be_empty
    expect(payload.evaluation.work_item_progress.map(&:candidate_id)).to eq([
      registration.dig(:input, :ordered_candidates, 0, :candidate_id)
    ])
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "durably denies a verified Candidate whose WorkItem has not selected or completed it" do
    registration = MergeSnapshotScenario.register(
      prefix: "auth-incomplete-progress",
      complete_work_item: false
    )
    verification = MergeSnapshotScenario.verify(registration, prefix: "auth-incomplete-progress")
    input = MergeSnapshotScenario.authorization_input(
      registration,
      verification,
      prefix: "auth-incomplete-progress"
    )

    result = operation.call(input).value!

    expect(result.data.outcome).to eq("denied")
    expect(result.data.reasons.map(&:code)).to include(
      "candidate_not_selected",
      "candidate_work_item_not_completed"
    )
    expect(result.data.work_item_progress).to be_empty
  end

  it "durably denies an unverified snapshot and a stale target-base observation" do
    unverified = MergeSnapshotScenario.register(prefix: "auth-unverified")
    placeholder = MergeSnapshotScenario.authorization_input(
      unverified,
      MergeSnapshotScenario.verify(unverified, prefix: "auth-temp"),
      prefix: "auth-unverified"
    )
    verified_stream = streams.merge_snapshot(unverified.dig(:input, :merge_snapshot_id))
    verification = event_store.read(verified_stream, Coordinator::Write::EventQueries::MERGE_SNAPSHOT_VERIFIED).sole
    # Preserve real command-produced history while presenting an exact different snapshot as the unverified case.
    other = MergeSnapshotScenario.register(
      prefix: "auth-actually-unverified",
      path: "lib/actually_unverified.rb",
      head_commit_oid: "e" * 40
    )
    input = placeholder.merge(
      command_id: "cmd-authorize-actually-unverified",
      merge_snapshot_id: other.dig(:input, :merge_snapshot_id),
      snapshot_binding: placeholder.fetch(:snapshot_binding).merge(
        registration_event: MergeSnapshotScenario.reference(other.fetch(:event)).to_h,
        snapshot_digest: other.fetch(:completion).data.snapshot_digest,
        verification_event: placeholder.dig(:snapshot_binding, :verification_event).merge(
          stream_id: other.dig(:input, :merge_snapshot_id)
        )
      )
    )

    denied = operation.call(input).value!
    expect(denied.data.outcome).to eq("denied")
    expect(denied.data.reasons.map(&:code)).to include("merge_snapshot_not_verified")

    stale = MergeSnapshotScenario.authorization_input(
      unverified,
      { payload: load(verification), event: verification },
      prefix: "auth-stale-base"
    )
    stale[:target_base_observation][:commit_oid] = "b" * 40
    stale_result = operation.call(stale).value!
    expect(stale_result.data.outcome).to eq("denied")
    expect(stale_result.data.reasons.map(&:code)).to include("target_base_binding_stale")
  end

  it "denies a missing gating obligation derived independently of Saga progress" do
    pair = CandidateObligationScenario.submit_pair(
      prefix: "auth-missing-obligation",
      separate_work_items: true
    )
    policy = CandidateObligationScenario.activate_policy(
      prefix: "auth-missing-obligation",
      change_set_id: pair.dig(:ids, :change_set_id),
      level: "merge_gate"
    )
    registration = MergeSnapshotScenario.register_candidates(
      prefix: "auth-missing-obligation",
      candidates: [ pair.fetch(:source), pair.fetch(:target) ]
    )
    verification = MergeSnapshotScenario.verify(registration, prefix: "auth-missing-obligation")
    input = MergeSnapshotScenario.authorization_input(
      registration,
      verification,
      prefix: "auth-missing-obligation",
      expected_impact_policy: MergeSnapshotScenario.expected_policy(policy)
    )

    result = operation.call(input).value!

    expect(result.data.outcome).to eq("denied")
    expect(result.data.reasons.map(&:code)).to eq([ "required_obligation_missing" ])
    expect(result.data.obligations.sole.status).to eq("missing")
  end

  it "denies an open exact obligation and grants once its required evidence is satisfied" do
    created = CandidateObligationScenario.create_obligation(
      prefix: "auth-obligation",
      separate_work_items: true
    )
    pair = created.fetch(:pair)
    registration = MergeSnapshotScenario.register_candidates(
      prefix: "auth-obligation",
      candidates: [ pair.fetch(:source), pair.fetch(:target) ]
    )
    verification = MergeSnapshotScenario.verify(registration, prefix: "auth-obligation")
    expected_policy = MergeSnapshotScenario.expected_policy(created.fetch(:policy))
    open_input = MergeSnapshotScenario.authorization_input(
      registration,
      verification,
      prefix: "auth-obligation-open",
      expected_impact_policy: expected_policy
    )

    open_result = operation.call(open_input).value!
    expect(open_result.data.outcome).to eq("denied")
    expect(open_result.data.reasons.map(&:code)).to eq([ "required_obligation_open" ])

    claim = CandidateObligationScenario.claim_obligation(
      created:,
      prefix: "auth-obligation",
      duration: 900
    )
    CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim:,
      command_id: "cmd-auth-obligation-combined",
      evidence_kind: "combined_tests"
    )
    CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim:,
      command_id: "cmd-auth-obligation-contract",
      evidence_kind: "contract_compatibility_review"
    )
    grant_input = open_input.merge(command_id: "cmd-authorize-auth-obligation-granted")
    grant = operation.call(grant_input).value!

    expect(grant.data.outcome).to eq("granted")
    expect(grant.data.obligations.sole.status).to eq("satisfied")
  end

  it "leaves Command replay ownership to the lifecycle while recording a fresh reevaluation" do
    registration = MergeSnapshotScenario.register(prefix: "auth-reuse")
    verification = MergeSnapshotScenario.verify(registration, prefix: "auth-reuse")
    input = MergeSnapshotScenario.authorization_input(registration, verification, prefix: "auth-reuse")
    first = operation.call(input).value!

    changed = input.merge(
      target_base_observation: input.fetch(:target_base_observation).merge(run_id: "another-run")
    )
    reevaluation = operation.call(changed).value!

    expect(reevaluation.data.authorization_id).not_to eq(first.data.authorization_id)
    expect(authorization_events(first.data.authorization_id).length).to eq(1)
    expect(authorization_events(reevaluation.data.authorization_id).length).to eq(1)
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  def authorization_events(authorization_id)
    event_store.read(
      streams.merge_authorization(authorization_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[MergeAuthorizationGranted MergeAuthorizationDenied],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end

  def load(event)
    registry.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
