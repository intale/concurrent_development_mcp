# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::ReleaseSetsV1, :read_model do
  subject(:projector) { described_class.new }

  let(:repository) { Coordinator::Read::Repositories::ReleaseSets.new }
  let(:release_set_id) { "RS-projection" }
  let(:change_set_id) { "CS-release-projection" }
  let(:repository_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000411
      018f0f4d-4e45-7abc-8def-000000000412
    ]
  end
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "serves lagging not-found content and converges idempotently without a freshness gate" do
    query = Coordinator::Read::Queries::ReleaseSetGet.new
    lagging = query.call(release_set_id:).value!
    expect(lagging.status).to eq("not_found")

    projector.call(prepared_event)
    projector.call(prepared_event)

    observed = query.call(release_set_id:).value!
    expect(observed.status).to eq("ok")
    expect(observed.warnings).to include("This view may lag the authoritative event store.")
    expect(observed.data.release_set).to have_attributes(
      release_set_id:,
      change_set_id:,
      status: "prepared"
    )
    expect(observed.data.release_set.ordered_members.map(&:repository_id)).to eq(repository_ids)
    expect(Coordinator::Read::ReleaseSet.count).to eq(1)
  end

  it "keeps the older view available while integration and verification lag, then converges in stream order" do
    projector.call(prepared_event)

    lagging = repository.fetch(release_set_id)
    expect(lagging).to have_attributes(
      status: "prepared",
      verification_status: "unverified",
      integrations: [],
      verifications: []
    )

    [ *integration_events, verification_event ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    observed = repository.fetch(release_set_id)
    expect(observed).to have_attributes(status: "verified", verification_status: "passed")
    expect(observed.integrations.map(&:repository_id)).to eq(repository_ids)
    expect(observed.verifications.map { _1.evidence.outcome }).to eq([ "passed" ])
  end

  it "serves verified content while activation completion lags and then converges idempotently" do
    [ prepared_event, *integration_events, verification_event ].each { projector.call(_1) }

    lagging = repository.fetch(release_set_id)
    expect(lagging).to have_attributes(status: "verified", activation: nil, completion: nil)

    [ activation_event, completion_event ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    observed = repository.fetch(release_set_id)
    expect(observed).to have_attributes(status: "completed")
    expect(observed.activation.activation_point.environment).to eq("production")
    expect(observed.completion).to have_attributes(outcome: "activated")
  end

  def prepared_event
    @prepared_event ||= release_event(
      Coordinator::Write::Events::ReleaseSetPreparedV1.new(
        release_set_id:,
        change_set_id:,
        ordered_members: repository_ids.each_with_index.map { member(_1, _2 + 1) },
        release_digest: digest("1"),
        policy_version: "release-set-preparation/v1",
        prepared_at: "2026-08-30T12:00:00.000000Z"
      ),
      revision: 0,
      position: 100,
      policy_version: "release-set-preparation/v1"
    )
  end

  def integration_events
    @integration_events ||= repository_ids.each_with_index.map do |repository_id, index|
      release_event(
        Coordinator::Write::Events::RepositoryIntegrationRecordedV1.new(
          release_set_id:,
          change_set_id:,
          release_digest: digest("1"),
          repository_id:,
          member_position: index + 1,
          attempt_id: "integration-attempt-#{index + 1}",
          attempt_number: 1,
          outcome: "integrated",
          merge_observation_event: source_reference(
            "MergeObserved", "MergeSnapshot", "MS-release-#{index + 1}", 3
          ),
          observation_digest: digest((index + 2).to_s),
          failure: nil,
          integration_digest: digest((index + 4).to_s),
          policy_version: "release-set-integration/v1",
          evidence_status: "attributed_unverified",
          recorded_at: "2026-08-30T12:0#{index + 1}:00.000000Z"
        ),
        revision: index + 1,
        position: 200 + (index * 100),
        policy_version: "release-set-integration/v1",
        causation_id: prepared_event.id
      )
    end
  end

  def verification_event
    @verification_event ||= release_event(
      Coordinator::Write::Events::ReleaseSetVerificationRecordedV1.new(
        release_set_id:,
        change_set_id:,
        release_digest: digest("1"),
        attempt_number: 1,
        integration_events: integration_events.map { event_reference(_1) },
        evidence: Coordinator::Write::ReleaseSets::VerificationEvidenceV1.new(
          producer: producer("release-tests"),
          run_id: "release-verification-run",
          environment_digest: digest("6"),
          result_digest: digest("7"),
          outcome: "passed",
          findings: [],
          produced_at: "2026-08-30T12:03:00.000000Z"
        ),
        verification_digest: digest("8"),
        policy_version: "release-set-verification/v1",
        evidence_status: "attributed_unverified",
        recorded_at: "2026-08-30T12:03:01.000000Z"
      ),
      revision: 3,
      position: 400,
      policy_version: "release-set-verification/v1",
      causation_id: integration_events.last.id
    )
  end

  def activation_event
    @activation_event ||= release_event(
      Coordinator::Write::Events::ReleaseSetActivatedV1.new(
        release_set_id:,
        change_set_id:,
        release_digest: digest("1"),
        verification_event: event_reference(verification_event),
        verification_digest: digest("8"),
        activation_point: Coordinator::Write::ReleaseSets::ActivationPointV1.new(
          kind: "deployment_manifest",
          environment: "production",
          external_reference: "deployment://release/projection",
          state_digest: digest("9"),
          producer: producer("deployment-controller"),
          run_id: "release-activation-run",
          activated_at: "2026-08-30T12:04:00.000000Z"
        ),
        activation_digest: digest("a"),
        policy_version: "release-set-activation/v1",
        evidence_status: "attributed_unverified",
        recorded_at: "2026-08-30T12:04:01.000000Z"
      ),
      revision: 4,
      position: 500,
      policy_version: "release-set-activation/v1",
      causation_id: verification_event.id
    )
  end

  def completion_event
    @completion_event ||= release_event(
      Coordinator::Write::Events::ReleaseSetCompletedV1.new(
        release_set_id:,
        change_set_id:,
        release_digest: digest("1"),
        outcome: "activated",
        source_event: event_reference(activation_event),
        compensation_evidence: [],
        completion_digest: digest("b"),
        rule_version: "release-set-completion/v1",
        completed_at: "2026-08-30T12:05:00.000000Z"
      ),
      revision: 5,
      position: 600,
      policy_version: "release-set-completion/v1",
      actor_kind: "system",
      causation_id: activation_event.id
    )
  end

  def member(repository_id, position)
    snapshot_id = "MS-release-#{position}"
    candidate_id = "CAN-release-#{position}"
    Coordinator::Write::ReleaseSets::MemberEvidenceV1.new(
      position:,
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      merge_snapshot_id: snapshot_id,
      change_set_id:,
      target_base_commit_oid: "a" * 40,
      merge_commit_oid: position.to_s * 40,
      snapshot_binding: Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
        registration_event: source_reference("MergeSnapshotRegistered", "MergeSnapshot", snapshot_id, 0),
        snapshot_digest: digest(position.to_s),
        verification_event: source_reference("MergeSnapshotVerified", "MergeSnapshot", snapshot_id, 2),
        verification_digest: digest((position + 2).to_s)
      ),
      authorization_event: source_reference(
        "MergeAuthorizationGranted", "MergeAuthorization", SecureRandom.uuid_v7, 0
      ),
      authorization_decision_digest: digest((position + 4).to_s),
      ordered_candidates: [
        Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(
          candidate_id:,
          change_set_id:,
          work_item_id: "WI-release-#{position}",
          attempt_id: "ATT-release-#{position}",
          repository_id:,
          target_branch: "main",
          object_format: "sha1",
          base_commit_oid: "a" * 40,
          head_commit_oid: position.to_s * 40,
          manifest_digest: digest((position + 6).to_s),
          candidate_event: source_reference("CandidateSubmitted", "Candidate", candidate_id, 0),
          manifest_event: source_reference("CandidateManifestDeclared", "Candidate", candidate_id, 1)
        )
      ]
    )
  end

  def release_event(payload, revision:, position:, policy_version:, actor_kind: "agent", causation_id: nil)
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.release_set(release_set_id),
      stream_revision: revision,
      global_position: position,
      policy_version:,
      command_id: "cmd-release-set-projection",
      actor_kind:,
      actor_id: actor_kind == "system" ? "release-set-lifecycle" : "release-agent",
      correlation_id:,
      causation_id:
    )
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: "DevelopmentIntegration",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def producer(name)
    Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(name:, version: "1.0")
  end

  def digest(character)
    "sha256:#{character * 64}"
  end
end
