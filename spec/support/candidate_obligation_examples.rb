# frozen_string_literal: true

module CandidateObligationExamples
  module_function

  TIMESTAMP = "2026-08-23T18:30:00.000000Z"
  RULE_VERSION = "candidate-compatibility-obligation/v1"

  def evidence(
    candidate_id:,
    registry_revision:,
    path:,
    observed_paths: [],
    produces: [],
    consumes: [],
    may_affect: [],
    assumes: [],
    repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
    change_set_id: "CS-obligation"
  )
    ids = Coordinator::Shared::IdGenerator.new
    candidate_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateSubmitted",
      stream_name: "Candidate",
      stream_id: candidate_id,
      revision: 0
    )
    manifest_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateChangeManifestCaptured",
      stream_name: "Candidate",
      stream_id: candidate_id,
      revision: 1
    )
    has_context = observed_paths.any?
    context_reference = if has_context
      reference(
        id: ids.uuid_v7,
        type: "CandidateBuildContextCaptured",
        stream_name: "Candidate",
        stream_id: candidate_id,
        revision: 2
      )
    end
    surface_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateImpactSurfaceDerived",
      stream_name: "Candidate",
      stream_id: candidate_id,
      revision: has_context ? 3 : 2
    )
    registration_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateImpactSurfaceRegistered",
      stream_name: "CandidateImpactRegistry",
      stream_id: change_set_id,
      revision: registry_revision
    )
    manifest_digest = digest(candidate_id, "manifest")
    context_digest = has_context ? digest(candidate_id, "context") : nil
    surface_digest = digest(candidate_id, "surface")
    head_character = registry_revision.even? ? "b" : "e"
    candidate = candidate_event(
      candidate_id:,
      change_set_id:,
      repository_id:,
      head_character:,
      manifest_digest:,
      context_digest:,
      path:
    )
    manifest = manifest_event(
      candidate_id:,
      repository_id:,
      head_character:,
      manifest_digest:,
      path:
    )
    context = if has_context
      context_event(
        candidate_id:,
        repository_id:,
        head_character:,
        context_digest:,
        observed_paths:
      )
    end
    surface = surface_event(
      candidate_id:,
      change_set_id:,
      repository_id:,
      head_character:,
      manifest_digest:,
      context_digest:,
      surface_digest:,
      produces:,
      consumes:,
      may_affect:,
      assumes:
    )
    registration = registration_event(
      candidate:,
      candidate_reference:,
      manifest_reference:,
      context_reference:,
      surface_reference:,
      surface_digest:
    )
    subject = Coordinator::Write::CandidateObligations::CandidateSubjectV1.new(
      candidate_id:,
      change_set_id:,
      work_item_id: candidate.work_item_id,
      attempt_id: candidate.attempt_id,
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_character * 40,
      manifest_digest:,
      build_context_digest: context_digest,
      surface_digest:,
      candidate_event: candidate_reference,
      manifest_event: manifest_reference,
      build_context_event: context_reference,
      surface_event: surface_reference,
      registration_event: registration_reference
    )
    Coordinator::Write::CandidateObligations::CandidateEvidenceV1.new(
      registration:,
      registration_event: registration_reference,
      candidate:,
      manifest:,
      build_context: context,
      surface:,
      subject:
    )
  end

  def policy(status: "gating", enforcement: "merge_gate")
    return Coordinator::Write::CandidateObligations::PolicyObservationV1.public_send(status) unless status == "gating"

    Coordinator::Write::CandidateObligations::PolicyObservationV1.gating(
      Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1.new(
        partition_event: partition_reference,
        partition: partition,
        head: decision_head,
        definition_digest: digest("policy", "definition"),
        change_set_id: "CS-obligation",
        required_evidence: %w[combined_tests contract_compatibility_review],
        enforcement:,
        valid_from: TIMESTAMP
      )
    )
  end

  def command(source:, target:, head: decision_head)
    identity = Coordinator::Write::CandidateObligations::IdentityBuilder.new.call(
      source:,
      target:,
      policy_partition_event: partition_reference,
      policy_head: head,
      rule_version: RULE_VERSION
    )
    Coordinator::Write::Commands::CreateCandidateCompatibilityObligation.new(
      command_id: identity.obligation_id,
      actor: { kind: "system", id: "candidate-impact-obligation-policy" },
      obligation_id: identity.obligation_id,
      source_registration: source.registration_event,
      target_registration: target.registration_event,
      policy_partition_event: partition_reference,
      policy_head: head,
      rule_version: RULE_VERSION
    )
  end

  def obligation
    source = evidence(
      candidate_id: "CAN-source",
      registry_revision: 0,
      path: "Gemfile.lock",
      produces: [ "dependency:rubygems:rails" ]
    )
    target = evidence(
      candidate_id: "CAN-target",
      registry_revision: 1,
      path: "app/services/checkout.rb",
      observed_paths: [ "Gemfile.lock" ],
      assumes: [ "dependency:rubygems:rails" ]
    )
    command = command(source:, target:)
    state = Coordinator::Write::Domain::CandidateObligations::State.new(
      source:,
      target:,
      policy: policy,
      existing: nil
    )

    Coordinator::Write::Domain::CandidateObligations::Create.new.call(
      state:,
      command:,
      created_at: TIMESTAMP
    ).value!.obligation
  end

  def decision_head
    @decision_head ||= begin
      event = reference(
        id: Coordinator::Shared::IdGenerator.new.uuid_v7,
        type: "DecisionActivated",
        stream_context: "HumanGuidance",
        stream_name: "Decision",
        stream_id: "D-obligation-policy",
        revision: 1
      )
      Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id: "D-obligation-policy",
        decision_revision: 1,
        event:
      )
    end
  end

  def partition
    Coordinator::Write::Decisions::DecisionPartitionV1.new(
      partition_id: "changeset:CS-obligation:candidate",
      topic_root: "candidate",
      anchor_kind: "changeset",
      anchor_id: "CS-obligation"
    )
  end

  def partition_reference
    @partition_reference ||= reference(
      id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type: "DecisionPartitionAdvanced",
      stream_context: "HumanGuidance",
      stream_name: "DecisionPartition",
      stream_id: partition.partition_id,
      revision: 0
    )
  end

  def reference(id:, type:, stream_name:, stream_id:, revision:, stream_context: "DevelopmentIntegration")
    Coordinator::Write::EventReference.new(
      event_id: id,
      type:,
      stream_context:,
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def digest(*parts)
    Coordinator::Shared::CanonicalJson.new.sha256(parts)
  end

  def candidate_event(candidate_id:, change_set_id:, repository_id:, head_character:, manifest_digest:, context_digest:, path:)
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      candidate_id:,
      change_set_id:,
      work_item_id: "W-obligation",
      attempt_id: "A-obligation",
      agent_id: "agent-a",
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_character * 40,
      checkpoint_kind: "final",
      lease_set_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_references: [ lease_reference(path) ],
      manifest_digest:,
      build_context_digest: context_digest,
      evidence_status: "attributed_unverified",
      submitted_at: TIMESTAMP
    )
  end

  def manifest_event(candidate_id:, repository_id:, head_character:, manifest_digest:, path:)
    Coordinator::Write::Events::CandidateChangeManifestCapturedV1.new(
      candidate_id:,
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_character * 40,
      evidence_revision: 1,
      policy_version: "candidate-change-manifest/v1",
      manifest_digest:,
      files: [ CandidateScenario.manifest_file(path) ],
      collector: collector,
      captured_at: TIMESTAMP
    )
  end

  def context_event(candidate_id:, repository_id:, head_character:, context_digest:, observed_paths:)
    Coordinator::Write::Events::CandidateBuildContextCapturedV1.new(
      candidate_id:,
      repository_id:,
      object_format: "sha1",
      head_commit_oid: head_character * 40,
      evidence_revision: 1,
      policy_version: "candidate-build-context/v1",
      build_context_digest: context_digest,
      inputs: observed_paths.map { { kind: "public_contract", path: _1, blob_oid: "d" * 40 } },
      environment: [],
      dependency_graph_digest: nil,
      test_environment_digest: nil,
      collector:,
      captured_at: TIMESTAMP
    )
  end

  def surface_event(
    candidate_id:,
    change_set_id:,
    repository_id:,
    head_character:,
    manifest_digest:,
    context_digest:,
    surface_digest:,
    produces:,
    consumes:,
    may_affect:,
    assumes:
  )
    Coordinator::Write::Events::CandidateImpactSurfaceDerivedV1.new(
      candidate_id:,
      change_set_id:,
      work_item_id: "W-obligation",
      attempt_id: "A-obligation",
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      head_commit_oid: head_character * 40,
      evidence_revision: 1,
      policy_version: "candidate-impact-surface/v1",
      surface_digest:,
      manifest_digest:,
      build_context_digest: context_digest,
      produces: produces.map { { impact_key: _1, before: nil, after: "changed" } },
      consumes: consumes.map { { impact_key: _1, value: "observed" } },
      may_affect: may_affect.map { { impact_key: _1 } },
      assumes: assumes.map { { impact_key: _1, predicate: "required" } },
      analyzer: { kind: "agent", id: "analyzer-1", analyzer_version: "impact-analyzer-v1" },
      evidence_status: "attributed_unverified",
      derived_at: TIMESTAMP
    )
  end

  def registration_event(
    candidate:,
    candidate_reference:,
    manifest_reference:,
    context_reference:,
    surface_reference:,
    surface_digest:
  )
    Coordinator::Write::Events::CandidateImpactSurfaceRegisteredV1.new(
      candidate_id: candidate.candidate_id,
      change_set_id: candidate.change_set_id,
      work_item_id: candidate.work_item_id,
      attempt_id: candidate.attempt_id,
      repository_id: candidate.repository_id,
      target_branch: candidate.target_branch,
      object_format: candidate.object_format,
      base_commit_oid: candidate.base_commit_oid,
      head_commit_oid: candidate.head_commit_oid,
      candidate_event: candidate_reference,
      manifest_event: manifest_reference,
      build_context_event: context_reference,
      surface_event: surface_reference,
      surface_digest:,
      index_policy_version: "candidate-impact-bucket-index/v1",
      registered_at: TIMESTAMP
    )
  end

  def lease_reference(path)
    {
      lease_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      resource_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      resource_kind: "file",
      resource_path: path,
      base_blob_oid: "c" * 40,
      fencing_token: 1
    }
  end

  def collector
    { kind: "agent", id: "collector-1", collector_version: "evidence-v1" }
  end
end
