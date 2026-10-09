# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CandidatesV1, :read_model, :event_store do
  subject(:projector) do
    described_class.new(
      submission_loader: Coordinator::Read::Candidates::SubmissionLoader.new(event_store:),
      impact_surface_loader: Coordinator::Read::Candidates::ImpactSurfaceLoader.new(event_store:)
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:event_factory) { Coordinator::Write::EventFactory.new }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:candidate_id) { "CAN-candidate-project" }
  let(:repository_id) { "01a03deb-6f55-74ba-bcc0-afd02e7b14dc" }
  let(:candidate_command_id) { SecureRandom.uuid_v7 }
  let(:task_id) { SecureRandom.uuid_v7 }
  let(:intention_set_id) { SecureRandom.uuid_v7 }
  let(:intention_id) { SecureRandom.uuid_v7 }
  let(:resource_id) { SecureRandom.uuid_v7 }
  let(:surface_id) { SecureRandom.uuid_v7 }
  let(:manifest_digest) { digest("a") }
  let(:build_context_digest) { digest("b") }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a") }
  let(:candidate_stream) { streams.candidate(candidate_id) }

  it "reconstructs the complete submitted Candidate at its terminal fact and stays idempotent" do
    events = persist_candidate_source
    submitted_event = events.fetch("CandidateSubmitted")

    # The candidate's authoritative source is its bounded history and registered
    # instruction; a CommandSucceeded event is neither written nor required.
    projector.call(submitted_event)
    projector.call(submitted_event)

    projected = repository.fetch(candidate_id)
    expect(projected).to have_attributes(
      evidence_status: "attributed_unverified",
      repository_id:,
      intention_set_id:,
      submitted: have_attributes(
        event: have_attributes(event_id: submitted_event.id, stream_revision: 9),
        global_position: submitted_event.global_position,
        occurred_at: submitted_event.created_at.utc.iso8601(6),
        persisted_at: submitted_event.created_at.utc.iso8601(6)
      )
    )
    expect(projected.manifest).to have_attributes(
      digest: manifest_digest,
      collector: have_attributes(kind: "agent", id: "agent-a", collector_version: "git-evidence-v1"),
      evidence: have_attributes(event: have_attributes(
        event_id: events.fetch("CandidateChangeManifestCaptured").id, stream_revision: 7
      ))
    )
    expect(projected.build_context).to have_attributes(
      digest: build_context_digest,
      evidence: have_attributes(event: have_attributes(
        event_id: events.fetch("CandidateBuildContextCaptured").id, stream_revision: 8
      ))
    )
    expect(Coordinator::Read::CandidateChangedResource.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(Coordinator::Read::CandidateObservedInput.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(Coordinator::Read::Candidate.count).to eq(1)
    expect(processed_events.count).to eq(1)
  end

  it "does not add a later intention to the immutable submitted instruction references" do
    submitted_event = persist_candidate_source.fetch("CandidateSubmitted")
    second_intention_id = SecureRandom.uuid_v7
    second_resource_id = SecureRandom.uuid_v7
    persist_intention(intention_id: second_intention_id, resource_id: second_resource_id)
    append_event(
      streams.work_intention_set(intention_set_id),
      Coordinator::Write::Events::WorkIntentionAddedToSetV1.new(
        set_id: intention_set_id, intention_id: second_intention_id, resource_id: second_resource_id
      ),
      metadata: candidate_metadata,
      markers: [ "work-intention-set:#{intention_set_id}", "intention:#{second_intention_id}" ]
    )

    submission = Coordinator::Read::Candidates::SubmissionLoader.new(event_store:).call(candidate_id)

    expect(submission.intentions.map(&:intention_id)).to eq([ intention_id ])
    expect(submission.intentions.map(&:resource_id)).to eq([ resource_id ])
    projector.call(submitted_event)
    expect(repository.fetch(candidate_id).intentions.map(&:intention_id)).to eq([ intention_id ])
  end

  it "rejects a persisted command-time fencing reference that differs from its declaration" do
    submitted_event = persist_candidate_source(reference_fence: 2).fetch("CandidateSubmitted")

    expect { projector.call(submitted_event) }.to raise_error(
      Coordinator::Read::InvalidProjectionSource,
      "Candidate command-time work-intention reference is inconsistent"
    )
    expect(processed_events).to be_empty
    expect(Coordinator::Read::Candidate).not_to exist(candidate_id:)
  end

  it "rolls back its idempotency claim when the exact Candidate history is incomplete" do
    submitted_event = persist_candidate_source(include_commit_range: false).fetch("CandidateSubmitted")

    expect { projector.call(submitted_event) }.to raise_error(
      Coordinator::Read::InvalidProjectionSource,
      "Candidate is missing CandidateCommitRangeDeclared"
    )
    expect(processed_events).to be_empty
    expect(Coordinator::Read::Candidate).not_to exist(candidate_id:)
  end

  it "loads the assigned impact surface and indexes its attributed keys idempotently" do
    events = persist_candidate_source
    submitted_event = events.fetch("CandidateSubmitted")
    surface_event = persist_impact_surface
    assignment_event = append_event(
      candidate_stream,
      Coordinator::Write::Events::CandidateImpactSurfaceAssignedV1.new(candidate_id:, surface_id:),
      metadata: candidate_metadata,
      markers: candidate_markers
    )

    projector.call(submitted_event)
    projector.call(assignment_event)
    projector.call(assignment_event)

    record = Coordinator::Read::Candidate.find(candidate_id)
    expect(record.impact_surface).to include(
      "surface_digest" => digest("d"),
      "evidence_status" => "attributed_unverified"
    )
    expect(
      Coordinator::Read::CandidateImpactKey.order(:direction).pluck(:direction, :impact_key)
    ).to contain_exactly(
      [ "produces", "contract:payments-api:v2" ],
      [ "consumes", "runtime:ruby" ],
      [ "may_affect", "framework:rails:callbacks" ],
      [ "assumes", "database:postgresql" ]
    )
    expect(repository.fetch(candidate_id).to_h.keys & %i[fresh pending projection_status]).to be_empty
    expect(processed_events.count).to eq(2)
    expect(surface_event.stream_revision).to eq(0)
  end

  def persist_candidate_source(include_commit_range: true, reference_fence: 1)
    return @persisted_candidate_source if @persisted_candidate_source && include_commit_range

    @candidate_reference_fence = reference_fence
    register_candidate_command
    append_task_submission
    persist_resource_and_intention
    append_event(
      streams.work_intention_set(intention_set_id),
      Coordinator::Write::Events::WorkIntentionSetCreatedV1.new(
        set_id: intention_set_id, attempt_id: command.attempt_id, work_item_id: command.work_item_id,
        change_set_id: command.change_set_id, repository_id:
      ),
      metadata: candidate_metadata,
      markers: [ "work-intention-set:#{intention_set_id}" ]
    )
    append_event(
      streams.work_intention_set(intention_set_id),
      Coordinator::Write::Events::WorkIntentionAddedToSetV1.new(
        set_id: intention_set_id, intention_id:, resource_id:
      ),
      metadata: candidate_metadata,
      markers: [ "work-intention-set:#{intention_set_id}", "intention:#{intention_id}" ]
    )

    facts = [
      Coordinator::Write::Events::CandidateCreatedV1.new(candidate_id:),
      Coordinator::Write::Events::CandidateAssignedToAttemptV1.new(
        candidate_id:, attempt_id: command.attempt_id, work_item_id: command.work_item_id,
        change_set_id: command.change_set_id
      ),
      Coordinator::Write::Events::CandidateAssignedToRepositoryV1.new(candidate_id:, repository_id:),
      Coordinator::Write::Events::CandidateTargetBranchSelectedV1.new(
        candidate_id:, target_branch: command.target_branch
      )
    ]
    if include_commit_range
      facts << Coordinator::Write::Events::CandidateCommitRangeDeclaredV1.new(
        candidate_id:, object_format: command.object_format,
        base_commit_oid: command.base_commit_oid, head_commit_oid: command.head_commit_oid
      )
    end
    facts.concat([
      Coordinator::Write::Events::CandidateCheckpointKindSelectedV1.new(
        candidate_id:, checkpoint_kind: command.checkpoint_kind
      ),
      Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1.new(
        candidate_id:, intention_set_id:
      ),
      manifest_payload,
      build_context_payload,
      Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:)
    ])

    events = facts.map do |fact|
      metadata = case fact
      when Coordinator::Write::Events::CandidateChangeManifestCapturedV2
        Coordinator::Write::Metadata::CandidateChangeManifestV2.new(
          **candidate_metadata.to_h,
          policy_version: "candidate-change-manifest/v1",
          collector: command.manifest.collector,
          manifest_digest:
        )
      when Coordinator::Write::Events::CandidateBuildContextCapturedV2
        Coordinator::Write::Metadata::CandidateBuildContextV2.new(
          **candidate_metadata.to_h,
          policy_version: "candidate-build-context/v1",
          collector: command.build_context.collector,
          build_context_digest:,
          dependency_graph_digest: digest("c"),
          test_environment_digest: nil
        )
      else
        candidate_metadata
      end
      [ fact.class.event_type, append_event(candidate_stream, fact, metadata:, markers: candidate_markers) ]
    end.to_h
    @persisted_candidate_source = events if include_commit_range
    events
  end

  def command(reference_fence: @candidate_reference_fence || 1)
    Coordinator::Write::Commands::SubmitCandidate.new(
      command_id: candidate_command_id,
      actor:,
      candidate_id:,
      change_set_id: "CS-candidate-project",
      work_item_id: "W-candidate-project",
      attempt_id: "A-candidate-project",
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "c" * 40,
      head_commit_oid: "d" * 40,
      checkpoint_kind: "final",
      intention_set_id:,
      intentions: [
        Coordinator::Write::WorkIntentionFencedReferenceV1.new(
          intention_id:, resource_id:, fencing_token: reference_fence
        )
      ],
      manifest: Coordinator::Write::Candidates::ChangeManifestV1.new(
        policy_version: "candidate-change-manifest/v1",
        digest: manifest_digest,
        files: manifest_payload.files,
        collector: evidence_collector("git-evidence-v1")
      ),
      build_context: Coordinator::Write::Candidates::BuildContextV1.new(
        policy_version: "candidate-build-context/v1",
        digest: build_context_digest,
        inputs: build_context_payload.inputs,
        environment: build_context_payload.environment,
        dependency_graph_digest: digest("c"),
        test_environment_digest: nil,
        collector: evidence_collector("build-context-v1")
      ),
      actual_resources: [
        Coordinator::Write::Candidates::ActualResourceV2.new(
          kind: "file", path: "lib/candidate.rb", base_blob_oid: "e" * 40
        )
      ]
    )
  end

  def register_candidate_command
    digest_value = Coordinator::Write::CommandInputDigest.new.call(command)
    append_event(
      streams.command(candidate_command_id),
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id: candidate_command_id,
        request_id: 1,
        tool_name: "candidate_submit"
      ),
      metadata: Coordinator::Write::Metadata::CanonicalCommandV1.new(
        command_id: candidate_command_id,
        actor_kind: actor.kind,
        actor_id: actor.id,
        recorded_by: "coordinator",
        policy_version: "coordination-task/v3",
        canonical_input_digest: digest_value
      ),
      markers: [ "command:#{candidate_command_id}" ]
    )
  end

  def append_task_submission
    append_event(
      streams.coordination_task(task_id),
      Coordinator::Write::Events::CoordinationTaskSubmittedV3.new(
        task_id:, command_id: candidate_command_id, tool_name: "candidate_submit",
        command_input: Coordinator::Write::CommandInputDigest.new.document(command),
        poll_interval_ms: 500, ttl_ms: nil
      ),
      metadata: Coordinator::Write::Metadata::CanonicalCommandV1.new(
        command_id: candidate_command_id,
        actor_kind: actor.kind,
        actor_id: actor.id,
        recorded_by: "coordinator",
        policy_version: "coordination-task/v3",
        canonical_input_digest: Coordinator::Write::CommandInputDigest.new.call(command)
      ),
      markers: [ "task:#{task_id}", "command:#{candidate_command_id}" ]
    )
  end

  def persist_resource_and_intention
    append_event(
      streams.resource(resource_id),
      Coordinator::Write::Events::ResourceIdentityV2::Registered.new(
        resource_id:, repository_id:, kind: "file", normalized_path: "lib/candidate.rb"
      ),
      metadata: candidate_metadata,
      markers: [ "resource:#{resource_id}", "repository:#{repository_id}" ]
    )
    persist_intention(intention_id:, resource_id:)
  end

  def persist_intention(intention_id:, resource_id:)
    append_event(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
        intention_id:, set_id: intention_set_id, resource_id:, repository_id:,
        change_set_id: command.change_set_id, work_item_id: command.work_item_id,
        attempt_id: command.attempt_id, agent_id: actor.id, mode: "shared",
        purpose: "Implement the assigned Candidate checkpoint", context: nil,
        object_format: "sha1", base_commit_oid: command.base_commit_oid,
        base_blob_oid: "e" * 40, fencing_token: 1,
        expires_at: "2026-10-10T00:00:00.000000Z"
      ),
      metadata: candidate_metadata,
      markers: [ "intention:#{intention_id}", "work-intention-set:#{intention_set_id}" ]
    )
  end

  def manifest_payload
    Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id:,
      evidence_revision: 1,
      files: [
        Coordinator::Write::Candidates::ManifestFileV1.new(
          status: "modified", old_path: "lib/candidate.rb", new_path: "lib/candidate.rb",
          old_blob_oid: "e" * 40, new_blob_oid: "f" * 40,
          old_mode: "100644", new_mode: "100644"
        )
      ]
    )
  end

  def build_context_payload
    Coordinator::Write::Events::CandidateBuildContextCapturedV2.new(
      candidate_id:,
      evidence_revision: 1,
      inputs: [
        Coordinator::Write::Candidates::BuildInputV1.new(
          kind: "public_contract", path: "lib/candidate.rb", blob_oid: "f" * 40
        )
      ],
      environment: [
        Coordinator::Write::Candidates::EnvironmentEntryV1.new(name: "RUBY_VERSION", value: RUBY_VERSION)
      ]
    )
  end

  def persist_impact_surface
    payload = Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2.new(
      surface_id:, candidate_id:, evidence_revision: 1,
      produces: [ Coordinator::Write::Candidates::ImpactTransitionV1.new(
        impact_key: "contract:payments-api:v2", before: nil, after: "available"
      ) ],
      consumes: [ Coordinator::Write::Candidates::ImpactObservationV1.new(
        impact_key: "runtime:ruby", value: "4.0"
      ) ],
      may_affect: [ Coordinator::Write::Candidates::ImpactKeyV1.new(
        impact_key: "framework:rails:callbacks"
      ) ],
      assumes: [ Coordinator::Write::Candidates::ImpactAssumptionV1.new(
        impact_key: "database:postgresql", predicate: ">= 17"
      ) ]
    )
    append_event(
      streams.candidate_impact_surface(surface_id), payload,
      metadata: Coordinator::Write::Metadata::CandidateImpactSurfaceV2.new(
        **candidate_metadata.to_h,
        actor_id: "analyzer-7",
        policy_version: "candidate-impact-surface/v1",
        analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
          kind: "agent", id: "analyzer-7", analyzer_version: "impact-analyzer-v1"
        ),
        manifest_digest:, build_context_digest:, surface_digest: digest("d")
      ),
      markers: [ "candidate:#{candidate_id}", "surface:#{surface_id}" ]
    )
  end

  def append_event(stream, payload, metadata:, markers:)
    event = event_factory.build!(
      event: payload,
      event_id: SecureRandom.uuid_v7,
      metadata:,
      markers:
    )
    event_store.append(stream, [ event ]).sole
  end

  def candidate_metadata
    Coordinator::Write::EventMetadata.new(
      command_id: candidate_command_id,
      actor_kind: actor.kind,
      actor_id: actor.id,
      recorded_by: "coordinator",
      policy_version: nil
    )
  end

  def candidate_markers
    [
      "candidate:#{candidate_id}", "repository:#{repository_id}",
      "change-set:#{command.change_set_id}", "work-item:#{command.work_item_id}",
      "attempt:#{command.attempt_id}", "work-intention-set:#{intention_set_id}",
      "command:#{candidate_command_id}"
    ]
  end

  def evidence_collector(version)
    Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent", id: actor.id, collector_version: version
    )
  end

  def digest(character)
    "sha256:#{character * 64}"
  end

  def repository
    @repository ||= Coordinator::Read::Repositories::Candidates.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "candidates", projection_version: 1
    )
  end
end
