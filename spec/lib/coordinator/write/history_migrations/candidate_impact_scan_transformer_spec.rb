# frozen_string_literal: true

RSpec.describe "history migration Candidate impact scan transformer", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:stream_allocator) { Coordinator::Container["history_migrations.stream_identity_allocator"] }
  let(:process_step_planner) { Coordinator::Container["history_migrations.process_step_planner"] }
  let(:target_event_planner) { Coordinator::Container["history_migrations.target_event_planner"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:legacy_repository_id) { SecureRandom.uuid_v7 }
  let(:legacy_change_set_id) { "legacy-scan-change-set" }
  let(:legacy_work_item_id) { "legacy-scan-work-item" }
  let(:legacy_attempt_id) { "legacy-scan-attempt" }
  let(:legacy_candidate_id) { "legacy-scan-candidate" }
  let(:legacy_decision_id) { "legacy-impact-policy" }
  let(:legacy_partition_id) { "legacy-impact-policy-partition" }
  let(:base_commit_oid) { "a" * 40 }
  let(:head_commit_oid) { "b" * 40 }
  let(:manifest_digest) { "sha256:#{'c' * 64}" }

  before { persist_scope_roots }

  it "rebuilds pair-scan selectors, source links, lifecycle facts, and the UUIDv7 scan stream" do
    candidate = persist_candidate_evidence
    policy = persist_policy
    scan_stream = stream("DevelopmentIntegration", "CandidateImpactPairScan", "legacy-pair-scan")
    started = persist_payload(scan_stream, pair_started_payload(candidate.fetch(:registration), policy))
    progressed = persist_payload(scan_stream, pair_progressed_payload(started, candidate.fetch(:registration), policy))
    completed = persist_payload(
      scan_stream,
      pair_completed_payload(started, progressed, candidate.fetch(:registration), policy)
    )
    upper_position = completed.global_position

    plan_candidate_evidence(candidate, upper_position:)
    plan_policy(policy, upper_position:)
    [ started, progressed, completed ].each do |source_event|
      expect(plan(source_event, upper_position:)).to be_success
    end

    started_facts = transform(started, upper_position:).value!
    progressed_fact = transform(progressed, upper_position:).value!.sole
    completed_fact = transform(completed, upper_position:).value!.sole
    lifecycle = started_facts.first
    links = started_facts.drop(1)

    expect(started_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::CandidateImpactPairScanStartedV2,
      Coordinator::Write::Events::CandidateImpactPairScanSourceLinkedV1,
      Coordinator::Write::Events::CandidateImpactPairScanSourceLinkedV1,
      Coordinator::Write::Events::CandidateImpactPairScanSourceLinkedV1
    ])
    expect(lifecycle.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(lifecycle.target_stream.stream_id).not_to eq("legacy-pair-scan")
    expect(lifecycle.event).to have_attributes(
      scan_id: lifecycle.target_stream.stream_id,
      direction: "outgoing",
      from_revision: 0,
      to_revision: 7,
      page_size: 50
    )
    expect(lifecycle.event.change_set_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(lifecycle.event.markers).not_to include("legacy-digest-routing-marker")
    expect(lifecycle.event.markers).to all(start_with("compound:candidate-impact-index:v2|"))
    expect(lifecycle.metadata_extension).to have_attributes(
      policy_version: "candidate-impact-pair-scan/v1",
      index_policy_version: Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION
    )
    expect(links.map { _1.event.role }).to eq(%w[source_registration policy_partition policy_head])
    expect(links.fetch(0).event.source.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    partition_kind, partition_anchor, partition_topic = links.fetch(1).event.source.stream_id.split(":", 3)
    expect([ partition_kind, partition_topic ]).to eq(%w[changeset candidate])
    expect(partition_anchor).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(links.fetch(2).event.source.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(links.map { _1.event.source.type }).to eq(
      %w[CandidateImpactSurfaceAssigned DecisionAddedToPartition DecisionActivated]
    )
    expect(progressed_fact.event).to have_attributes(
      scan_id: lifecycle.event.scan_id,
      page_number: 1,
      next_from_revision: 3,
      markers: lifecycle.event.markers
    )
    expect(progressed_fact.event.to_h).not_to have_key(:previous_checkpoint)
    expect(progressed_fact.event.to_h).not_to have_key(:total_registration_count)
    expect(completed_fact.event.to_h.keys).to contain_exactly(:scan_id)
    expect([ lifecycle, progressed_fact, completed_fact ].map(&:target_stream).uniq.one?).to be(true)

    writes = [ started, progressed, completed ].map do |source_event|
      dispatch(source_event, upper_position:).value!
    end
    persisted = target_store.read(
      lifecycle.target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          CandidateImpactPairScanStarted CandidateImpactPairScanSourceLinked
          CandidateImpactPairScanProgressed CandidateImpactPairScanCompleted
        ],
        maximum_count: 6,
        direction: :asc
      )
    )

    expect(writes.sum { _1.events.length }).to eq(6)
    expect(persisted.map(&:type)).to eq(%w[
      CandidateImpactPairScanStarted
      CandidateImpactPairScanSourceLinked
      CandidateImpactPairScanSourceLinked
      CandidateImpactPairScanSourceLinked
      CandidateImpactPairScanProgressed
      CandidateImpactPairScanCompleted
    ])
    expect(persisted.map(&:stream_revision)).to eq((0..5).to_a)
    expect(persisted.first.metadata.fetch("index_policy_version")).to eq(
      Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION
    )
    expect(persisted.flat_map { _1.data.keys }).not_to include(
      "started_at", "progressed_at", "completed_at", "page_registration_count", "page_count"
    )
  end

  it "keeps a skipped registry sweep available with remapped policy sources and no state dump" do
    policy = persist_policy
    scan_stream = stream("DevelopmentIntegration", "CandidateImpactRegistrySweep", "legacy-registry-sweep")
    skipped = persist_payload(scan_stream, registry_skipped_payload(policy))
    upper_position = skipped.global_position
    plan_policy(policy, upper_position:)

    expect(plan(skipped, upper_position:)).to be_success
    facts = transform(skipped, upper_position:).value!

    expect(facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::CandidateImpactRegistrySweepSkippedV2,
      Coordinator::Write::Events::CandidateImpactRegistrySweepSourceLinkedV1,
      Coordinator::Write::Events::CandidateImpactRegistrySweepSourceLinkedV1
    ])
    expect(facts.first.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(facts.first.event.to_h).to eq(
      scan_id: facts.first.target_stream.stream_id,
      reason: "empty_registry"
    )
    expect(facts.drop(1).map { _1.event.role }).to eq(%w[policy_partition policy_head])
    expect(facts.drop(1).map { _1.event.source.type }).to eq(
      %w[DecisionAddedToPartition DecisionActivated]
    )
    expect(facts.first.metadata_extension.policy_version).to eq(
      "candidate-impact-registry-sweep/v1"
    )
  end

  it "keeps a skipped pair scan linked to rebuilt Candidate and policy facts" do
    candidate = persist_candidate_evidence
    policy = persist_policy
    scan_stream = stream("DevelopmentIntegration", "CandidateImpactPairScan", "legacy-skipped-pair-scan")
    skipped = persist_payload(scan_stream, pair_skipped_payload(candidate.fetch(:registration), policy))
    upper_position = skipped.global_position
    plan_candidate_evidence(candidate, upper_position:)
    plan_policy(policy, upper_position:)

    expect(plan(skipped, upper_position:)).to be_success
    facts = transform(skipped, upper_position:).value!

    expect(facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::CandidateImpactPairScanSkippedV2,
      Coordinator::Write::Events::CandidateImpactPairScanSourceLinkedV1,
      Coordinator::Write::Events::CandidateImpactPairScanSourceLinkedV1,
      Coordinator::Write::Events::CandidateImpactPairScanSourceLinkedV1
    ])
    expect(facts.first.event.reason).to eq("no_predecessors")
    expect(facts.drop(1).map { _1.event.role }).to eq(%w[source_registration policy_partition policy_head])
    expect(facts.flat_map(&:markers)).not_to include("legacy-digest-routing-marker")
    expect(facts.first.metadata_extension.index_policy_version).to eq(
      Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION
    )
  end

  it "trims registry-sweep progress and completion counters while retaining its bounded cursor" do
    policy = persist_policy
    scan_stream = stream("DevelopmentIntegration", "CandidateImpactRegistrySweep", "legacy-running-registry-sweep")
    started = persist_payload(scan_stream, registry_started_payload(policy))
    progressed = persist_payload(scan_stream, registry_progressed_payload(started, policy))
    completed = persist_payload(scan_stream, registry_completed_payload(started, progressed, policy))
    upper_position = completed.global_position
    plan_policy(policy, upper_position:)
    [ started, progressed, completed ].each do |source_event|
      expect(plan(source_event, upper_position:)).to be_success
    end

    started_facts = transform(started, upper_position:).value!
    progressed_fact = transform(progressed, upper_position:).value!.sole
    completed_fact = transform(completed, upper_position:).value!.sole

    expect(started_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::CandidateImpactRegistrySweepStartedV2,
      Coordinator::Write::Events::CandidateImpactRegistrySweepSourceLinkedV1,
      Coordinator::Write::Events::CandidateImpactRegistrySweepSourceLinkedV1
    ])
    expect(progressed_fact.event).to have_attributes(
      scan_id: started_facts.first.event.scan_id,
      page_number: 1,
      next_from_revision: 3,
      change_set_id: started_facts.first.event.change_set_id,
      to_revision: 7,
      page_size: 50
    )
    expect(progressed_fact.event.to_h).not_to have_key(:total_registration_count)
    expect(completed_fact.event.to_h.keys).to contain_exactly(:scan_id)
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

  def dispatch(source_event, upper_position:)
    dispatcher.call(
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

  def persist_candidate_evidence
    candidate_stream = stream("DevelopmentIntegration", "Candidate", legacy_candidate_id)
    submitted = persist_payload(candidate_stream, candidate_payload)
    manifest = persist_payload(candidate_stream, manifest_payload)
    surface = persist_payload(candidate_stream, surface_payload)
    registration = persist_payload(
      stream("DevelopmentIntegration", "CandidateImpactRegistry", legacy_change_set_id),
      registration_payload(submitted, manifest, surface)
    )
    { submitted:, manifest:, surface:, registration: }
  end

  def persist_policy
    decision_event = persist_raw(
      stream("HumanGuidance", "Decision", legacy_decision_id),
      type: "DecisionActivated"
    )
    head = Coordinator::Write::Decisions::DecisionHeadV1.new(
      decision_id: legacy_decision_id,
      decision_revision: decision_event.stream_revision,
      event: event_reference(decision_event)
    )
    partition = Coordinator::Write::Decisions::DecisionPartitionV1.new(
      partition_id: legacy_partition_id,
      topic_root: "candidate",
      anchor_kind: "changeset",
      anchor_id: legacy_change_set_id
    )
    partition_event = persist_payload(
      stream("HumanGuidance", "DecisionPartition", legacy_partition_id),
      Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
        partition:,
        partition_revision: 0,
        decision: head,
        active_decisions: [ head ],
        change_kind: "activated",
        advanced_at: "2001-07-01T00:05:00.000000Z"
      )
    )
    { head:, decision_event:, partition_event: }
  end

  def plan_candidate_evidence(candidate, upper_position:)
    %i[submitted manifest surface registration].each do |name|
      expect(plan(candidate.fetch(name), upper_position:)).to be_success
    end
  end

  def plan_policy(policy, upper_position:)
    expect(
      plan_reference(
        policy.fetch(:decision_event),
        upper_position:,
        target_stream_name: "Decision",
        identity_role: "decision",
        target_event_type: "DecisionActivated",
        target_step_name: "activate-decision"
      )
    ).to be_success
    expect(plan(policy.fetch(:partition_event), upper_position:)).to be_success
  end

  def plan_reference(
    source_event,
    upper_position:,
    target_stream_name:,
    identity_role:,
    target_event_type:,
    target_step_name:
  )
    raise "source position outside test migration window" if source_event.global_position > upper_position

    allocation = stream_allocator.call(
      migration_id:,
      source_config_name: "default",
      source_event:,
      target_stream_context: "HumanGuidance",
      target_stream_name:,
      identity_role:
    )
    return allocation if allocation.failure?

    process_step = process_step_planner.call(
      source_event:,
      process_name: "history-migration-#{migration_id}",
      step_name: target_step_name,
      subject_kind: "source-event",
      subject_id: source_event.id,
      rule_version: "history-migration-transformation/v1",
      allocate_target_entity: true
    )
    target_event_planner.call(
      migration_id:,
      source_event:,
      transformation_step: target_step_name,
      target_stream: allocation.value!.target_stream,
      target_event_id: process_step.target_entity_id!,
      target_event_type:,
      caused_by: process_step.event
    )
  end

  def candidate_payload
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id: legacy_candidate_id,
      change_set_id: legacy_change_set_id,
      work_item_id: legacy_work_item_id,
      attempt_id: legacy_attempt_id,
      agent_id: "agent-scan",
      repository_id: legacy_repository_id,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid:,
      head_commit_oid:,
      checkpoint_kind: "final",
      lease_set_id: SecureRandom.uuid_v7,
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
      build_context_digest: nil,
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
      files: [
        Coordinator::Write::Candidates::ManifestFileV1.new(
          status: "modified",
          old_path: "lib/example.rb",
          new_path: "lib/example.rb",
          old_blob_oid: base_commit_oid,
          new_blob_oid: head_commit_oid,
          old_mode: "100644",
          new_mode: "100644"
        )
      ],
      collector: collector,
      captured_at: "2001-07-01T00:01:00.000000Z"
    )
  end

  def surface_payload
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
      surface_digest: "sha256:#{'d' * 64}",
      manifest_digest:,
      build_context_digest: nil,
      produces: [
        Coordinator::Write::Candidates::ImpactTransitionV1.new(
          impact_key: "schema:candidate",
          before: nil,
          after: "v2"
        )
      ],
      consumes: [],
      may_affect: [],
      assumes: [],
      analyzer: Coordinator::Write::Candidates::ImpactAnalyzerV1.new(
        kind: "agent",
        id: "agent-scan",
        analyzer_version: "candidate-impact/v1"
      ),
      evidence_status: "attributed_unverified",
      derived_at: "2001-07-01T00:02:00.000000Z"
    )
  end

  def registration_payload(submitted, manifest, surface)
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
      build_context_event: nil,
      surface_event: event_reference(surface),
      surface_digest: "sha256:#{'d' * 64}",
      index_policy_version: Coordinator::Write::Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION,
      registered_at: "2001-07-01T00:03:00.000000Z"
    )
  end

  def pair_started_payload(registration, policy)
    Coordinator::Write::Events::CandidateImpactPairScanStartedV1.new(
      scan_id: "legacy-pair-scan",
      change_set_id: legacy_change_set_id,
      source_registration: event_reference(registration),
      direction: "outgoing",
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      markers: [ "legacy-digest-routing-marker" ],
      from_revision: 0,
      to_revision: 7,
      page_size: 50,
      index_policy_version: "candidate-impact-bucket-index/v1",
      rule_version: "candidate-impact-pair-scan/v1",
      started_at: "2001-07-01T00:06:00.000000Z"
    )
  end

  def pair_progressed_payload(started, registration, policy)
    Coordinator::Write::Events::CandidateImpactPairScanProgressedV1.new(
      scan_id: "legacy-pair-scan",
      change_set_id: legacy_change_set_id,
      source_registration: event_reference(registration),
      direction: "outgoing",
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      markers: [ "legacy-digest-routing-marker" ],
      started_event: event_reference(started),
      previous_checkpoint: event_reference(started),
      previous_from_revision: 0,
      next_from_revision: 3,
      to_revision: 7,
      page_size: 50,
      page_number: 1,
      page_registration_count: 2,
      total_registration_count: 2,
      index_policy_version: "candidate-impact-bucket-index/v1",
      rule_version: "candidate-impact-pair-scan/v1",
      progressed_at: "2001-07-01T00:07:00.000000Z"
    )
  end

  def pair_completed_payload(started, progressed, registration, policy)
    Coordinator::Write::Events::CandidateImpactPairScanCompletedV1.new(
      scan_id: "legacy-pair-scan",
      change_set_id: legacy_change_set_id,
      source_registration: event_reference(registration),
      direction: "outgoing",
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      markers: [ "legacy-digest-routing-marker" ],
      started_event: event_reference(started),
      previous_checkpoint: event_reference(progressed),
      previous_from_revision: 3,
      final_from_revision: 8,
      to_revision: 7,
      page_size: 50,
      page_count: 2,
      page_registration_count: 1,
      total_registration_count: 3,
      index_policy_version: "candidate-impact-bucket-index/v1",
      rule_version: "candidate-impact-pair-scan/v1",
      completed_at: "2001-07-01T00:08:00.000000Z"
    )
  end

  def pair_skipped_payload(registration, policy)
    Coordinator::Write::Events::CandidateImpactPairScanSkippedV1.new(
      scan_id: "legacy-skipped-pair-scan",
      change_set_id: legacy_change_set_id,
      source_registration: event_reference(registration),
      direction: "outgoing",
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      markers: [ "legacy-digest-routing-marker" ],
      from_revision: 0,
      to_revision: -1,
      page_size: 50,
      reason: "no_predecessors",
      index_policy_version: "candidate-impact-bucket-index/v1",
      rule_version: "candidate-impact-pair-scan/v1",
      skipped_at: "2001-07-01T00:08:30.000000Z"
    )
  end

  def registry_skipped_payload(policy)
    Coordinator::Write::Events::CandidateImpactRegistrySweepSkippedV1.new(
      scan_id: "legacy-registry-sweep",
      change_set_id: legacy_change_set_id,
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      from_revision: 0,
      to_revision: -1,
      page_size: 50,
      reason: "empty_registry",
      rule_version: "candidate-impact-registry-sweep/v1",
      skipped_at: "2001-07-01T00:09:00.000000Z"
    )
  end

  def registry_started_payload(policy)
    Coordinator::Write::Events::CandidateImpactRegistrySweepStartedV1.new(
      scan_id: "legacy-running-registry-sweep",
      change_set_id: legacy_change_set_id,
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      from_revision: 0,
      to_revision: 7,
      page_size: 50,
      rule_version: "candidate-impact-registry-sweep/v1",
      started_at: "2001-07-01T00:10:00.000000Z"
    )
  end

  def registry_progressed_payload(started, policy)
    Coordinator::Write::Events::CandidateImpactRegistrySweepProgressedV1.new(
      scan_id: "legacy-running-registry-sweep",
      change_set_id: legacy_change_set_id,
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      started_event: event_reference(started),
      previous_checkpoint: event_reference(started),
      previous_from_revision: 0,
      next_from_revision: 3,
      to_revision: 7,
      page_size: 50,
      page_number: 1,
      page_registration_count: 2,
      total_registration_count: 2,
      rule_version: "candidate-impact-registry-sweep/v1",
      progressed_at: "2001-07-01T00:11:00.000000Z"
    )
  end

  def registry_completed_payload(started, progressed, policy)
    Coordinator::Write::Events::CandidateImpactRegistrySweepCompletedV1.new(
      scan_id: "legacy-running-registry-sweep",
      change_set_id: legacy_change_set_id,
      policy_partition_event: event_reference(policy.fetch(:partition_event)),
      policy_head: policy.fetch(:head),
      started_event: event_reference(started),
      previous_checkpoint: event_reference(progressed),
      previous_from_revision: 3,
      final_from_revision: 8,
      to_revision: 7,
      page_size: 50,
      page_count: 2,
      page_registration_count: 1,
      total_registration_count: 3,
      rule_version: "candidate-impact-registry-sweep/v1",
      completed_at: "2001-07-01T00:12:00.000000Z"
    )
  end

  def collector
    @collector ||= Coordinator::Write::Candidates::EvidenceCollectorV1.new(
      kind: "agent",
      id: "agent-scan",
      collector_version: "git-diff-tree/v1"
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
            "command_id" => "legacy-scan-command",
            "actor_kind" => "agent",
            "actor_id" => "agent-scan",
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
