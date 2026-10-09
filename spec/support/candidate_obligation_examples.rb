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
    manifest_digest = digest(candidate_id, "manifest")
    context_digest = observed_paths.any? ? digest(candidate_id, "context") : nil
    surface_digest = digest(candidate_id, "surface")
    head_character = registry_revision.even? ? "b" : "e"
    manifest = Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id:,
      evidence_revision: 1,
      files: [ CandidateScenario.manifest_file(path) ]
    )
    build_context = if observed_paths.any?
      Coordinator::Write::Events::CandidateBuildContextCapturedV2.new(
        candidate_id:,
        evidence_revision: 1,
        inputs: observed_paths.map { { kind: "public_contract", path: _1, blob_oid: "d" * 40 } },
        environment: []
      )
    end
    manifest_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateChangeManifestCaptured",
      stream_name: "Candidate",
      stream_id: candidate_id,
      revision: 7
    )
    context_reference = if build_context
      reference(
        id: ids.uuid_v7,
        type: "CandidateBuildContextCaptured",
        stream_name: "Candidate",
        stream_id: candidate_id,
        revision: 8
      )
    end
    candidate_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateSubmitted",
      stream_name: "Candidate",
      stream_id: candidate_id,
      revision: build_context ? 9 : 8
    )
    surface_id = ids.uuid_v7
    surface_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateImpactSurfaceDerived",
      stream_name: "CandidateImpactSurface",
      stream_id: surface_id,
      revision: 0
    )
    registration_reference = reference(
      id: ids.uuid_v7,
      type: "CandidateImpactSurfaceAssigned",
      stream_name: "Candidate",
      stream_id: candidate_id,
      revision: build_context ? 10 : 9
    )
    surface = Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2.new(
      surface_id:,
      candidate_id:,
      evidence_revision: 1,
      produces: produces.map { { impact_key: _1, before: nil, after: "changed" } },
      consumes: consumes.map { { impact_key: _1, value: "observed" } },
      may_affect: may_affect.map { { impact_key: _1 } },
      assumes: assumes.map { { impact_key: _1, predicate: "required" } }
    )
    assignment = Coordinator::Write::Events::CandidateImpactSurfaceAssignedV1.new(
      candidate_id:,
      surface_id:
    )
    candidate = Coordinator::Write::Candidates::StateV2.new(
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
      intention_set_id: ids.uuid_v7,
      manifest_digest:,
      build_context_digest: context_digest,
      manifest:,
      build_context:,
      submission_event: candidate_reference,
      manifest_event: manifest_reference,
      build_context_event: context_reference,
      surface_id:,
      surface_assignment_event: registration_reference,
      latest_revision: registration_reference.stream_revision
    )
    subject = Coordinator::Write::CandidateObligations::CandidateSubjectV1.new(
      candidate_id:,
      change_set_id:,
      work_item_id: candidate.work_item_id,
      attempt_id: candidate.attempt_id,
      repository_id:,
      target_branch: candidate.target_branch,
      object_format: candidate.object_format,
      base_commit_oid: candidate.base_commit_oid,
      head_commit_oid: candidate.head_commit_oid,
      manifest_digest:,
      build_context_digest: context_digest,
      surface_digest:,
      candidate_event: candidate_reference,
      manifest_event: manifest_reference,
      build_context_event: context_reference,
      surface_event: surface_reference,
      registration_event: registration_reference
    )

    Coordinator::Write::CandidateObligations::CandidateEvidenceV2.new(
      registration: assignment,
      registration_event: registration_reference,
      registration_global_position: registry_revision,
      candidate:,
      surface:,
      surface_event: surface_reference,
      surface_digest:,
      subject:
    )
  end

  def policy(status: "gating", enforcement: "merge_gate")
    return Coordinator::Write::CandidateObligations::PolicyObservationV1.public_send(status) unless status == "gating"

    Coordinator::Write::CandidateObligations::PolicyObservationV1.gating(
      Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1.new(
        partition_event: partition_reference,
        partition:,
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
    ids = Coordinator::Shared::IdGenerator.new
    Coordinator::Write::Commands::CreateCandidateCompatibilityObligation.new(
      command_id: ids.uuid_v7,
      actor: { kind: "system", id: "candidate-impact-obligation-policy" },
      obligation_id: ids.uuid_v7,
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
    policy_observation = policy
    matcher = Coordinator::Write::CandidateObligations::Matcher.new
    reasons = matcher.call(source:, target:)
    state = Coordinator::Write::Domain::CandidateObligations::State.new(
      source:,
      target:,
      policy: policy_observation,
      existing: nil
    )
    decision = Coordinator::Write::Domain::CandidateObligations::Create.new.call(
      state:,
      command:
    ).value!
    created = decision.plan.events.fetch(0)
    validity = Coordinator::Write::CandidateObligations::ValidityBuilder.new.call(
      source:,
      target:,
      policy: policy_observation.evidence,
      reasons:,
      rule_version: RULE_VERSION
    )

    definition(created:, source:, target:, policy_observation:, reasons:, validity:)
  end

  def definition(created:, source:, target:, policy_observation: policy, reasons: nil, validity: nil)
    reasons ||= Coordinator::Write::CandidateObligations::Matcher.new.call(source:, target:)
    validity ||= Coordinator::Write::CandidateObligations::ValidityBuilder.new.call(
      source:,
      target:,
      policy: policy_observation.evidence,
      reasons:,
      rule_version: RULE_VERSION
    )
    Coordinator::Write::VerificationObligations::DefinitionV2.new(
      obligation_id: created.obligation_id,
      kind: created.kind,
      change_set_id: source.subject.change_set_id,
      source_candidate: source.subject,
      target_candidate: target.subject,
      reasons:,
      required_evidence: created.required_evidence,
      enforcement: created.enforcement,
      policy: policy_observation.evidence,
      validity_input_digest: validity.digest,
      rule_version: RULE_VERSION,
      created_at: TIMESTAMP
    )
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
      type: "DecisionAddedToPartition",
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
end
