# frozen_string_literal: true

RSpec.describe "history migration Candidate transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-candidate-change-set" }
  let(:legacy_work_item_id) { "legacy-candidate-work-item" }
  let(:legacy_attempt_id) { "legacy-candidate-attempt" }
  let(:legacy_candidate_id) { "legacy-candidate" }
  let(:intention_set_id) { SecureRandom.uuid_v7 }
  let(:base_commit_oid) { "a" * 40 }
  let(:head_commit_oid) { "b" * 40 }
  let(:manifest_digest) { "sha256:#{'c' * 64}" }
  let(:build_context_digest) { "sha256:#{'d' * 64}" }
  let(:candidate_stream) do
    stream("DevelopmentIntegration", "Candidate", legacy_candidate_id)
  end

  before { persist_scope_roots }

  it "splits a legacy submission, coalesces its duplicate Attempt attachment, and rebinds WorkItem selection" do
    submitted = persist_payload(candidate_stream, candidate_payload)
    expect(plan(submitted, upper_position: submitted.global_position)).to be_success

    facts = transform(submitted, upper_position: submitted.global_position).value!

    expect(facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::CandidateCreatedV1,
      Coordinator::Write::Events::CandidateAssignedToAttemptV1,
      Coordinator::Write::Events::CandidateAssignedToRepositoryV1,
      Coordinator::Write::Events::CandidateTargetBranchSelectedV1,
      Coordinator::Write::Events::CandidateCommitRangeDeclaredV1,
      Coordinator::Write::Events::CandidateCheckpointKindSelectedV1,
      Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1,
      Coordinator::Write::Events::CandidateSubmittedV3
    ])
    expect(facts.map(&:target_stream).uniq.one?).to be(true)
    expect(facts.first.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(facts.first.target_stream.stream_id).not_to eq(legacy_candidate_id)
    expect(facts.fetch(1).event.to_h.values_at(:attempt_id, :work_item_id, :change_set_id)).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(facts.fetch(6).event.intention_set_id).to eq(intention_set_id)
    expect(facts.fetch(6).metadata_extension.policy_version).to eq(
      Coordinator::Write::LeaseResourceV2::POLICY_VERSION
    )
    expect(facts.map { _1.metadata_extension.attributed_actor.id }.uniq).to eq([ "agent-candidate" ])
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(
      :submitted_at,
      :lease_references,
      :manifest_digest,
      :build_context_digest,
      :evidence_status
    )

    attachment = persist_payload(
      stream("DevelopmentExecution", "Attempt", legacy_attempt_id),
      attachment_payload(submitted)
    )
    expect(transform(attachment, upper_position: attachment.global_position).value!).to be_empty

    selected = persist_payload(
      stream("DevelopmentExecution", "WorkItem", legacy_work_item_id),
      Coordinator::Write::Events::WorkItemCandidateSelectedV1.new(
        work_item_id: legacy_work_item_id,
        change_set_id: legacy_change_set_id,
        attempt_id: legacy_attempt_id,
        candidate_id: legacy_candidate_id,
        candidate_event: event_reference(submitted),
        selected_at: "2001-07-01T00:03:00.000000Z"
      )
    )
    selected_fact = transform(selected, upper_position: selected.global_position).value!.sole

    expect(selected_fact.event).to be_a(Coordinator::Write::Events::WorkItemCandidateSelectedV2)
    expect(selected_fact.event.candidate_id).to eq(facts.first.target_stream.stream_id)
    expect(selected_fact.event.candidate_event).to have_attributes(
      type: "CandidateSubmitted",
      stream_id: facts.first.target_stream.stream_id
    )
    expect(selected_fact.event.candidate_event.event_id).not_to eq(submitted.id)
    expect(selected_fact.event.to_h).not_to have_key(:selected_at)
  end

  it "migrates Candidate evidence and a digest-derived head registry into typed metadata and a UUIDv7 stream" do
    submitted = persist_payload(candidate_stream, candidate_payload)
    manifest = persist_payload(candidate_stream, manifest_payload)
    context = persist_payload(candidate_stream, build_context_payload)
    head = persist_payload(
      stream("DevelopmentIntegration", "CandidateHead", "sha256:#{'e' * 64}"),
      head_payload(submitted)
    )
    upper_position = head.global_position
    [ submitted, manifest, context, head ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    manifest_fact = transform(manifest, upper_position:).value!.sole
    context_fact = transform(context, upper_position:).value!.sole
    head_fact = transform(head, upper_position:).value!.sole

    expect(manifest_fact.event).to be_a(Coordinator::Write::Events::CandidateChangeManifestCapturedV2)
    expect(manifest_fact.metadata_extension).to have_attributes(
      collector: collector,
      manifest_digest:,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA
    )
    expect(context_fact.event).to be_a(Coordinator::Write::Events::CandidateBuildContextCapturedV2)
    expect(context_fact.metadata_extension).to have_attributes(
      collector:,
      build_context_digest:,
      dependency_graph_digest: "sha256:#{'f' * 64}",
      test_environment_digest: nil,
      policy_version: Coordinator::Write::Candidates::BuildContextDocumentV1::SCHEMA
    )
    expect(head_fact.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(head_fact.event.registry_id).to eq(head_fact.target_stream.stream_id)
    expect(head_fact.event.repository_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(head_fact.metadata_extension.marker_codec_version).to eq(
      Coordinator::Write::Candidates::HeadIdentityBuilder::MARKER_CODEC_VERSION
    )
    expect(head_fact.markers).not_to include("sha256:#{'e' * 64}")

    writes = [ submitted, manifest, context, head ].map do |event|
      HistoryMigrationWaveDispatch.call(
        dispatcher:,
        migration_id:,
        source_config_name: "default",
        source_upper_position: upper_position,
        source_event: event
      ).value!
    end
    target_events = writes.flat_map(&:events)
    candidate_contract = Coordinator::Read::Contracts::CandidateSourceEvent.new
    target_events.select { candidate_contract.class::EVENT_TYPES.include?(_1.type) }.each do |event|
      validation = HistoryMigrationProjectionContract.call(event, candidate_contract)
      expect(validation).to be_success, validation.errors.to_h.inspect
    end
    persisted_manifest = target_events.find { _1.type == "CandidateChangeManifestCaptured" }
    persisted_context = target_events.find { _1.type == "CandidateBuildContextCaptured" }
    persisted_head = target_events.find { _1.type == "CandidateHeadRegistered" }

    expect(persisted_manifest.metadata).to include(
      "actor_id" => "agent-candidate",
      "manifest_digest" => manifest_digest,
      "collector" => collector.to_h.transform_keys(&:to_s)
    )
    expect(persisted_context.metadata).to include(
      "build_context_digest" => build_context_digest,
      "dependency_graph_digest" => "sha256:#{'f' * 64}",
      "collector" => collector.to_h.transform_keys(&:to_s)
    )
    expect(persisted_head.metadata.fetch("marker_codec_version")).to eq(
      Coordinator::Write::Candidates::HeadIdentityBuilder::MARKER_CODEC_VERSION
    )
    expect(target_store.read_at(head_fact.target_stream, 0).id).to eq(persisted_head.id)
  end

  it "routes a transitional V2 head reference through its legacy Candidate submission" do
    submitted = persist_payload(candidate_stream, candidate_payload)
    head = persist_payload(
      stream("DevelopmentIntegration", "CandidateHead", SecureRandom.uuid_v7),
      Coordinator::Write::HistoryMigrations::PostRemodelEvents::CandidateHeadRegisteredV2.new(
        registry_id: SecureRandom.uuid_v7,
        candidate_id: legacy_candidate_id,
        attempt_id: legacy_attempt_id,
        repository_id: legacy_repository_id,
        object_format: "sha1",
        head_commit_oid:,
        candidate_event: event_reference(submitted),
        registered_at: "2001-07-01T00:02:00.000000Z"
      )
    )
    upper_position = head.global_position
    expect(plan(submitted, upper_position:)).to be_success

    submitted_facts = transform(submitted, upper_position:).value!
    result = transform(head, upper_position:)

    expect(result).to be_success
    fact = result.value!.sole
    expect(fact.event).to have_attributes(
      candidate_id: submitted_facts.first.target_stream.stream_id,
      attempt_id: submitted_facts.fetch(1).event.attempt_id,
      repository_id: submitted_facts.fetch(2).event.repository_id,
      object_format: "sha1",
      head_commit_oid:
    )
    expect(fact.event.registry_id).to eq(fact.target_stream.stream_id)
  end

  it "moves an impact surface to its own UUIDv7 stream and rebuilds the Candidate assignment index" do
    submitted = persist_payload(candidate_stream, candidate_payload)
    manifest = persist_payload(candidate_stream, manifest_payload)
    context = persist_payload(candidate_stream, build_context_payload)
    surface = persist_payload(candidate_stream, impact_surface_payload)
    registration = persist_payload(
      stream("DevelopmentIntegration", "CandidateImpactRegistry", legacy_change_set_id),
      impact_registration_payload(submitted, manifest, context, surface)
    )
    upper_position = registration.global_position
    [ submitted, manifest, context, surface ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    surface_fact = transform(surface, upper_position:).value!.sole
    assignment_fact = transform(registration, upper_position:).value!.sole

    expect(surface_fact.event).to be_a(Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2)
    expect(surface_fact.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(surface_fact.event.surface_id).to eq(surface_fact.target_stream.stream_id)
    expect(surface_fact.metadata_extension).to have_attributes(
      analyzer:,
      manifest_digest:,
      build_context_digest:,
      surface_digest: "sha256:#{'1' * 64}",
      policy_version: Coordinator::Write::Candidates::ImpactSurfaceDocumentV1::SCHEMA
    )
    expect(assignment_fact.event).to be_a(
      Coordinator::Write::Events::CandidateImpactSurfaceAssignedV1
    )
    expect(assignment_fact.event.surface_id).to eq(surface_fact.target_stream.stream_id)
    expect(assignment_fact.target_stream.stream_id).to eq(surface_fact.event.candidate_id)
    expect(assignment_fact.markers.grep(/candidate-impact-index/)).not_to be_empty
    expect(assignment_fact.event.to_h.keys).to contain_exactly(:candidate_id, :surface_id)
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def plan(source_event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def persist_scope_roots
    persist_raw(stream("DevelopmentPlanning", "Repository", legacy_repository_id), type: "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", legacy_change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", legacy_work_item_id), type: "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "Attempt", legacy_attempt_id), type: "AttemptAuthorized")
  end

  def candidate_payload
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      agent_id: "agent-candidate",
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      checkpoint_kind: "final",
      lease_set_id: intention_set_id,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: SecureRandom.uuid_v7,
          resource_id: SecureRandom.uuid_v7,
          resource_kind: "file",
          resource_path: "lib/example.rb",
          base_blob_oid: base_commit_oid,
          fencing_token: 1
        )
      ],
      manifest_digest:,
      build_context_digest:,
      evidence_status: "attributed_unverified",
      submitted_at: "2001-07-01T00:00:00.000000Z"
    )
  end

  def manifest_payload
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id: legacy_candidate_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA,
      manifest_digest:,
      files: [ manifest_file ],
      collector:,
      captured_at: "2001-07-01T00:01:00.000000Z"
    )
  end

  def build_context_payload
    Coordinator::Write::Events::CandidateBuildContextCapturedV1.new(
      candidate_id: legacy_candidate_id,
      repository_id: legacy_repository_id,
      object_format: "sha1",
      head_commit_oid:,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::BuildContextDocumentV1::SCHEMA,
      build_context_digest:,
      inputs: [
        Coordinator::Write::Candidates::BuildInputV1.new(
          kind: "runtime_version",
          path: ".ruby-version",
          blob_oid: "2" * 40
        )
      ],
      environment: [
        Coordinator::Write::Candidates::EnvironmentEntryV1.new(
          name: "RSPEC",
          value: "green"
        )
      ],
      dependency_graph_digest: "sha256:#{'f' * 64}",
      test_environment_digest: nil,
      collector:,
      captured_at: "2001-07-01T00:01:30.000000Z"
    )
  end

  def head_payload(submitted)
    Coordinator::Write::Events::CandidateHeadRegisteredV1.new(
      registry_id: "sha256:#{'e' * 64}",
      candidate_id: legacy_candidate_id,
      attempt_id: legacy_attempt_id,
      repository_id: legacy_repository_id,
      object_format: "sha1",
      head_commit_oid:,
      candidate_event: event_reference(submitted),
      registered_at: "2001-07-01T00:02:00.000000Z"
    )
  end

  def attachment_payload(submitted)
    Coordinator::Write::Events::CandidateAttachedToAttemptV1.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      checkpoint_kind: "final",
      manifest_digest:,
      build_context_digest:,
      candidate_event: event_reference(submitted),
      attached_at: "2001-07-01T00:02:30.000000Z"
    )
  end

  def impact_surface_payload
    Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      head_commit_oid:,
      evidence_revision: 1,
      policy_version: Coordinator::Write::Candidates::ImpactSurfaceDocumentV1::SCHEMA,
      surface_digest: "sha256:#{'1' * 64}",
      manifest_digest:,
      build_context_digest:,
      produces: [
        Coordinator::Write::Candidates::ImpactTransitionV1.new(
          impact_key: "schema:candidate",
          before: nil,
          after: "v2"
        )
      ],
      consumes: [
        Coordinator::Write::Candidates::ImpactObservationV1.new(
          impact_key: "api:mcp",
          value: "v1"
        )
      ],
      may_affect: [
        Coordinator::Write::Candidates::ImpactKeyV1.new(impact_key: "read-model:candidate")
      ],
      assumes: [
        Coordinator::Write::Candidates::ImpactAssumptionV1.new(
          impact_key: "database:postgresql",
          predicate: "available"
        )
      ],
      analyzer:,
      evidence_status: "attributed_unverified",
      derived_at: "2001-07-01T00:02:00.000000Z"
    )
  end

  def impact_registration_payload(submitted, manifest, context, surface)
    Coordinator::Write::Events::CandidateImpactSurfaceRegisteredV1.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      candidate_event: event_reference(submitted),
      manifest_event: event_reference(manifest),
      build_context_event: event_reference(context),
      surface_event: event_reference(surface),
      surface_digest: "sha256:#{'1' * 64}",
      index_policy_version: Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION,
      registered_at: "2001-07-01T00:02:30.000000Z"
    )
  end

  def manifest_file
    Coordinator::Write::Candidates::ManifestFileV1.new(
      status: "modified",
      old_path: "lib/example.rb",
      new_path: "lib/example.rb",
      old_blob_oid: base_commit_oid,
      new_blob_oid: head_commit_oid,
      old_mode: "100644",
      new_mode: "100644"
    )
  end

  def collector
    @collector ||= Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent",
      id: "agent-candidate",
      collector_version: "git-diff-tree/v1"
    )
  end

  def analyzer
    @analyzer ||= Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
      kind: "agent",
      id: "agent-candidate",
      analyzer_version: "candidate-impact/v1"
    )
  end

  def persist_payload(target_stream, payload)
    persist_raw(
      target_stream,
      type: payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version
    )
  end

  def persist_raw(target_stream, type:, data: {}, schema_version: 1)
    source_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => "legacy-candidate-command",
            "actor_kind" => "agent",
            "actor_id" => "agent-candidate",
            "recorded_by" => "coordinator"
          },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
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
end
