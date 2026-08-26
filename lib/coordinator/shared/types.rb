# frozen_string_literal: true

module Coordinator::Shared
  module Types
    include Dry.Types()

    IDENTIFIER_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{0,199}\z/
    REPOSITORY_ID_PATTERN = /\A[a-z0-9][a-z0-9._-]{0,99}\z/
    GIT_OID_PATTERN = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/
    SHA256_DIGEST_PATTERN = /\Asha256:[0-9a-f]{64}\z/
    TIMESTAMP_PATTERN = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/
    UUID_V7_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    RESOURCE_PATH_PATTERN = /\A[^\u0000-\u001f\u007f]{1,1024}\z/
    CANDIDATE_IMPACT_KEY_PATTERN = /\A[a-z][a-z0-9_.-]*(?::[a-z0-9][a-z0-9_.-]*)+\z/
    MARKER_PURPOSE_PATTERN = /\A[a-z][a-z0-9-]{0,63}\z/
    MARKER_COMPONENT_PATTERN = /\A(?!compound:)[^\u0000\r\n]{1,512}\z/
    SKILL_ID_PATTERN = /\Askill:v1:[0-9a-f]{64}\z/
    SKILL_MEDIA_TYPE_PATTERN = /\A[\x21-\x7e]{1,255}\z/
    DEVELOPMENT_ARTIFACT_ID_PATTERN = /\Aartifact:v1:[0-9a-f]{64}\z/
    DEVELOPMENT_ARTIFACT_RELATION_ID_PATTERN = /\Aartifact-relation:v1:[0-9a-f]{64}\z/

    SKILL_NAME_MAXIMUM_BYTES = 128
    SKILL_SCOPE_MAXIMUM_BYTES = 256
    SKILL_DESCRIPTION_MAXIMUM_BYTES = 2_048
    SKILL_INSTRUCTIONS_MAXIMUM_BYTES = 262_144
    SKILL_ASSET_MAXIMUM_COUNT = 64
    SKILL_ASSET_PATH_MAXIMUM_BYTES = 512
    SKILL_ASSET_MAXIMUM_BYTES = 1_048_576
    SKILL_ASSETS_TOTAL_MAXIMUM_BYTES = 4_194_304
    SKILL_ASSET_BASE64_MAXIMUM_BYTES = 1_398_104
    DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES = 256
    DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES = 512
    DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES = 128
    DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT = 32
    DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES = 2_048
    DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES = 512
    DEVELOPMENT_ARTIFACT_COLLECTOR_MAXIMUM_BYTES = 256
    DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES = 2_097_152
    DEVELOPMENT_ARTIFACT_CONTENT_BASE64_MAXIMUM_BYTES = 2_796_204
    DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT = 128
    DEVELOPMENT_ARTIFACT_RELATION_PATH_MAXIMUM_BYTES = 2_048
    DEVELOPMENT_ARTIFACT_RELATION_FRAGMENT_MAXIMUM_BYTES = 1_024
    DEVELOPMENT_ARTIFACT_RELATION_SUPERSESSION_REASON_MAXIMUM_BYTES = 1_000
    DEVELOPMENT_ARTIFACT_HISTORY_MAXIMUM_COUNT = 1 + (DEVELOPMENT_ARTIFACT_RELATION_MAXIMUM_COUNT * 2)
    DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES = 2_048
    DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS = 100
    DEVELOPMENT_ARTIFACT_KINDS = %w[
      build_manifest
      build_plan
      event_model
      contract
      implementation_record
      verification_evidence
      decision_log
      decision_record
      governance
      documentation
      web_research
      repository_checkpoint
      performance_profile
      import_manifest
      external_reference
      other
    ].freeze
    DEVELOPMENT_ARTIFACT_SOURCE_KINDS = %w[
      local_file
      generated
      git_commit
      downloaded_document
      web_page
      web_search
      other
    ].freeze
    DEVELOPMENT_ARTIFACT_RELATION_KINDS = %w[
      documents
      evidences
      derived_from
      supersedes
      references
      contains
      produced_by_import
    ].freeze
    DEVELOPMENT_ARTIFACT_TARGET_KINDS = %w[
      artifact
      build
      decision
      skill
      repository
      checkpoint
      external
    ].freeze
    OPERATION_BATCH_MAXIMUM_ITEMS = 1_000
    OPERATION_BATCH_PAGE_SIZE = 50
    OPERATION_BATCH_QUERY_MAXIMUM_ITEMS = 100
    OPERATION_BATCH_MAXIMUM_ENCODED_BYTES = 3_145_728
    OPERATION_BATCH_MAXIMUM_HISTORY_EVENTS = 1_024
    WRITE_SET_RESOURCE_MAXIMUM_COUNT = 32
    CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT = WRITE_SET_RESOURCE_MAXIMUM_COUNT
    RESOURCE_KEY_POLICY_VERSIONS = %w[
      coordinator-resource-key/v1
      coordinator-resource-key/v2
    ].freeze

    ACTOR_KINDS = %w[
      agent
      user
      orchestrator
      integrator
      repository_adapter
      system
    ].freeze
    DEPENDENCY_KINDS = %w[
      requires_completion
      requires_candidate
      requires_artifact
      requires_contract
      must_integrate_after
      must_deploy_after
      requires_composite_verification
    ].freeze
    OUTPUT_REQUIRED_DEPENDENCY_KINDS = %w[
      requires_artifact
      requires_contract
      requires_composite_verification
    ].freeze
    WORK_ITEM_OUTPUT_KINDS = %w[artifact contract].freeze
    DEPENDENCY_REQUIRED_OUTPUT_KINDS = %w[artifact contract verification_run].freeze
    WORK_ITEM_OUTPUT_MAXIMUM_COUNT = 32
    GIT_OBJECT_FORMATS = %w[sha1 sha256].freeze
    GUIDANCE_SOURCES = %w[mcp_client agent_forwarded].freeze
    STATEMENT_KINDS = %w[
      directive
      preference
      approval
      rejection
      fact
      goal
      priority
      evaluation
      question
      hypothesis
    ].freeze
    DECISION_EFFECTS = %w[
      require
      forbid
      prefer
      avoid
      allow
      select
      defer
      approve
      reject
      prioritize
    ].freeze
    DECISION_MODALITIES = %w[must must_not should should_not may].freeze
    DECISION_VALUE_SCHEMAS = %w[named-choice/v1 string-set/v1 target-action/v1].freeze
    INTERPRETATION_ASSESSMENT_STATUSES = %w[
      accepted_for_activation
      confirmation_required
      needs_classification
    ].freeze
    INTERPRETATION_ADJUDICATION_ACTIONS = %w[
      accept
      reject
      request_clarification
    ].freeze
    INTERPRETATION_CLARIFICATION_STATUSES = %w[
      confirmation_required
      needs_classification
    ].freeze
    INTERPRETATION_CLARIFICATION_ORIGINS = %w[
      proposal_assessment
      adjudication
    ].freeze
    INTERPRETATION_LIFECYCLE_STATUSES = %w[
      proposed
      clarification_required
      accepted
      rejected
    ].freeze
    INTERPRETATION_ADJUDICATION_OUTCOMES = %w[
      accepted_for_activation
      rejected
      clarification_required
    ].freeze
    DECISION_ACTIVATION_OUTCOMES = %w[activated].freeze
    DECISION_CORRECTION_OUTCOMES = %w[corrected].freeze
    DECISION_POLICY_STATUSES = %w[recorded active].freeze
    DECISION_PARTITION_ANCHOR_KINDS = %w[
      workspace
      repo
      changeset
      workitem
      attempt
      candidate
    ].freeze
    DECISION_CHANGE_KINDS = %w[activated corrected].freeze
    AGENT_CHOICE_TYPES = %w[testing.framework].freeze
    AGENT_CHOICE_ASSESSMENT_BASES = %w[no_policy compliant advisory_violation].freeze
    AGENT_CHOICE_POLICY_EVALUATION_STATUSES = %w[
      allowed
      blocked
      confirmation_required
      conflict
      unsupported
      unresolved
    ].freeze
    AGENT_CHOICE_POLICY_EVALUATION_BASES = %w[
      no_policy
      compliant
      advisory_violation
      blocking_violation
      confirmation_required
      decision_conflict
      unsupported_context
      unresolved_head
    ].freeze
    AGENT_CHOICE_POLICY_REASON_CODES = %w[
      no_active_decision
      selected_option_satisfies_decision
      selected_option_violates_advisory_decision
      selected_option_violates_blocking_decision
      selected_option_requires_confirmation
      tied_most_specific_decisions
      unsupported_decision_context
      unresolved_decision_head
    ].freeze
    AGENT_CHOICE_OUTCOMES = %w[accepted].freeze
    AGENT_CHOICE_OBSERVATION_STATUSES = %w[recorded accepted invalidated].freeze
    AGENT_CHOICE_IMPACT_POLICY_VERSIONS = %w[agent-choice-decision-impact/v1].freeze
    AGENT_CHOICE_IMPACT_SCAN_STATUSES = %w[absent running skipped completed].freeze
    AGENT_CHOICE_IMPACT_SCAN_SKIP_REASONS = %w[future_only candidate_scope artifact_scope].freeze
    AGENT_CHOICE_IMPACT_ASSESSMENT_OUTCOMES = %w[
      still_valid
      invalidated
      not_applicable
      already_invalidated
    ].freeze
    AGENT_CHOICE_IMPACT_ASSESSMENT_REASONS = %w[
      compliant_or_advisory
      noncompliance_preceded_change
      attempt_not_active
      change_already_observed
      choice_terminal
      blocking_policy_introduced
      confirmation_policy_introduced
      decision_conflict_introduced
      unsupported_policy_introduced
      unresolved_policy_introduced
    ].freeze
    AGENT_CHOICE_INVALIDATION_REASONS = %w[
      blocking_policy_introduced
      confirmation_policy_introduced
      decision_conflict_introduced
      unsupported_policy_introduced
      unresolved_policy_introduced
    ].freeze
    CANDIDATE_CHECKPOINT_KINDS = %w[intermediate handoff final].freeze
    CANDIDATE_MANIFEST_STATUSES = %w[
      added
      modified
      deleted
      renamed
      copied
      type_changed
      submodule_changed
    ].freeze
    CANDIDATE_GIT_FILE_MODES = %w[100644 100755 120000 160000].freeze
    CANDIDATE_BUILD_INPUT_KINDS = %w[
      dependency_manifest
      dependency_lockfile
      runtime_version
      toolchain_config
      public_contract
      generated_source_origin
    ].freeze
    CANDIDATE_EVIDENCE_STATUSES = %w[attributed_unverified].freeze
    CANDIDATE_IMPACT_SURFACE_DIRECTIONS = %w[produces consumes may_affect assumes].freeze
    CANDIDATE_IMPACT_QUERY_DIRECTIONS = %w[incoming outgoing].freeze
    CANDIDATE_IMPACT_RELATIONSHIP_KINDS = %w[potentially_affects].freeze
    CANDIDATE_IMPACT_REASON_KINDS = %w[
      changed_resource_overlap
      observed_input_changed
      semantic_key_match
    ].freeze
    CANDIDATE_IMPACT_INDEX_ROLES = %w[source target].freeze
    CANDIDATE_IMPACT_INDEX_KINDS = %w[path semantic].freeze
    CANDIDATE_IMPACT_INDEX_BUCKETS = ("0".."9").to_a.concat(("a".."f").to_a).freeze
    CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS = %w[
      disabled
      advisory
      verification_gate
      merge_gate
    ].freeze
    CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS = %w[
      combined_tests
      agent_compatibility_review
      contract_compatibility_review
      schema_migration_review
      security_review
    ].freeze
    CANDIDATE_COMPATIBILITY_OBLIGATION_RULE_VERSIONS = %w[
      candidate-compatibility-obligation/v1
    ].freeze
    CANDIDATE_IMPACT_INDEX_POLICY_VERSIONS = %w[candidate-impact-bucket-index/v1].freeze
    CANDIDATE_IMPACT_REGISTRY_SWEEP_RULE_VERSIONS = %w[candidate-impact-registry-sweep/v1].freeze
    CANDIDATE_IMPACT_PAIR_SCAN_RULE_VERSIONS = %w[candidate-impact-pair-scan/v1].freeze
    CANDIDATE_IMPACT_SCAN_STATUSES = %w[absent running skipped completed].freeze
    CANDIDATE_IMPACT_REGISTRY_SWEEP_SKIP_REASONS = %w[
      stale_policy
      non_gating_policy
      inactive_policy
      empty_registry
    ].freeze
    CANDIDATE_IMPACT_PAIR_SCAN_SKIP_REASONS = %w[
      stale_policy
      non_gating_policy
      inactive_policy
      no_predecessors
      no_routing_markers
    ].freeze
    VERIFICATION_OBLIGATION_KINDS = %w[candidate_compatibility].freeze
    VERIFICATION_OBLIGATION_STATUSES = %w[open satisfied failed waived invalidated].freeze
    VERIFICATION_OBLIGATION_CLAIM_STATES = %w[unclaimed active expired].freeze
    VERIFICATION_OBLIGATION_WAIVER_REASON_CODES = %w[
      duplicate
      accepted_risk
      not_required
      external_approval
      other
    ].freeze
    VERIFICATION_OBLIGATION_INVALIDATION_RULE_VERSIONS = %w[
      verification-obligation-validity/v1
    ].freeze
    VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATUSES = %w[absent running completed].freeze
    VERIFICATION_EVIDENCE_CONCLUSIONS = %w[
      passed
      failed
      inconclusive
      not_applicable
    ].freeze
    VERIFICATION_EVIDENCE_FINDING_SEVERITIES = %w[
      info
      warning
      error
      critical
    ].freeze
    VERIFICATION_EVIDENCE_MAXIMUM_COUNT = 32
    MERGE_SNAPSHOT_EVIDENCE_STATUSES = %w[attributed_unverified].freeze
    MERGE_SNAPSHOT_REGISTRATION_POLICY_VERSIONS = %w[merge-snapshot-registration/v1].freeze
    MERGE_SNAPSHOT_MAXIMUM_CANDIDATES = 32
    MERGE_SNAPSHOT_VERIFICATION_EVIDENCE_KINDS = %w[combined_tests].freeze
    MERGE_SNAPSHOT_VERIFICATION_POLICY_VERSIONS = %w[merge-snapshot-verification/v1].freeze
    MERGE_SNAPSHOT_VERIFICATION_STATUSES = %w[
      unverified
      failed
      inconclusive
      not_applicable
      verified
    ].freeze
    MERGE_SNAPSHOT_VERIFICATION_MAXIMUM_COUNT = 32
    MERGE_AUTHORIZATION_POLICY_VERSIONS = %w[merge-authorization/v1].freeze
    MERGE_AUTHORIZATION_OUTCOMES = %w[granted denied].freeze
    MERGE_AUTHORIZATION_POLICY_STATUSES = %w[
      absent
      disabled
      advisory
      verification_gate
      merge_gate
    ].freeze
    MERGE_AUTHORIZATION_OBLIGATION_STATUSES = %w[
      missing
      open
      satisfied
      failed
      waived
      invalidated
    ].freeze
    MERGE_AUTHORIZATION_REASON_CODES = %w[
      merge_snapshot_not_found
      merge_snapshot_binding_stale
      merge_snapshot_not_verified
      target_base_binding_stale
      mixed_change_set_snapshot
      candidate_work_item_not_member
      candidate_work_item_scope_invalid
      candidate_not_selected
      candidate_selection_mismatch
      candidate_work_item_not_completed
      candidate_completion_mismatch
      candidate_dependency_unsatisfied
      impact_policy_context_stale
      candidate_impact_surface_missing
      required_obligation_missing
      required_obligation_open
      required_obligation_failed
      required_obligation_invalidated
      authorization_history_invalid
    ].freeze
    MERGE_AUTHORIZATION_MAXIMUM_OBLIGATIONS =
      MERGE_SNAPSHOT_MAXIMUM_CANDIDATES * (MERGE_SNAPSHOT_MAXIMUM_CANDIDATES - 1)
    MERGE_AUTHORIZATION_MAXIMUM_REASONS = 1_024
    MERGE_OBSERVATION_POLICY_VERSIONS = %w[merge-observation/v1].freeze
    RELEASE_SET_PREPARATION_POLICY_VERSIONS = %w[release-set-preparation/v1].freeze
    RELEASE_SET_MINIMUM_MEMBERS = 2
    RELEASE_SET_MAXIMUM_MEMBERS = 16
    RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS = 8
    RELEASE_SET_VERIFICATION_MAXIMUM_ATTEMPTS = 8
    RELEASE_SET_LIFECYCLE_MAXIMUM_EVENTS = 140
    RELEASE_SET_INTEGRATION_POLICY_VERSIONS = %w[release-set-integration/v1].freeze
    RELEASE_SET_VERIFICATION_POLICY_VERSIONS = %w[release-set-verification/v1].freeze
    RELEASE_SET_ACTIVATION_POLICY_VERSIONS = %w[release-set-activation/v1].freeze
    RELEASE_SET_COMPENSATION_RULE_VERSIONS = %w[release-set-compensation/v1].freeze
    RELEASE_SET_COMPLETION_RULE_VERSIONS = %w[release-set-completion/v1].freeze
    RELEASE_SET_INTEGRATION_OUTCOMES = %w[integrated failed].freeze
    RELEASE_SET_VERIFICATION_OUTCOMES = %w[passed failed].freeze
    RELEASE_SET_ACTIVATION_POINT_KINDS = %w[deployment_manifest configuration feature_flag].freeze
    RELEASE_SET_COMPENSATION_ACTIONS = %w[rollback revert feature_flag_disable].freeze
    RELEASE_SET_COMPENSATION_TRIGGER_KINDS = %w[repository_integration_failed release_verification_failed].freeze
    RELEASE_SET_COMPLETION_OUTCOMES = %w[activated compensated].freeze
    CANDIDATE_OBLIGATION_POLICY_STATUSES = %w[
      stale
      non_gating
      inactive
      gating
    ].freeze
    CANDIDATE_OBLIGATION_DECISION_OUTCOMES = %w[
      created
      replayed
      stale_policy
      non_gating_policy
      inactive_policy
      no_match
    ].freeze
    DECISION_ACTIVATION_INELIGIBILITY_REASONS = %w[
      non_normative_statement_kind
      missing_effect
      missing_modality
      scope_unresolved
      lifecycle_relation_requires_specific_command
      validity_elapsed
      until_event_requires_expiry_policy
      topic_registry_mismatch
    ].freeze
    DECISION_CORRECTION_INELIGIBILITY_REASONS = %w[
      non_normative_statement_kind
      missing_effect
      missing_modality
      scope_unresolved
      until_event_requires_expiry_policy
      validity_future
      validity_elapsed
      topic_registry_mismatch
    ].freeze
    SCOPE_PROVENANCE_KINDS = %w[explicit inferred unresolved].freeze
    SCOPE_ANCHOR_LEVELS = %w[workspace repository change_set work_item attempt unresolved].freeze
    DECISION_PHASES = %w[planning implementation verification integration deployment].freeze
    ENFORCEMENT_LEVELS = %w[
      disabled
      advisory
      planning_gate
      implementation_gate
      verification_gate
      merge_gate
      deployment_gate
    ].freeze
    RETROACTIVITY_KINDS = %w[
      future_only
      active_attempts
      all_unverified_candidates
      all_unmerged_candidates
      all_artifacts
    ].freeze
    VIOLATION_ACTIONS = %w[warn block block_and_replan require_confirmation].freeze
    RESOLUTION_STRATEGIES = %w[single_choice set_union manual_resolution].freeze
    MERGE_TARGET_KINDS = %w[candidate change_set repository].freeze
    MERGE_ACTIONS = %w[defer approve reject].freeze
    SUPPORTED_INTERPRETATION_TOPICS = %w[
      candidate.impact_policy
      testing.framework
      testing.required_suites
      implementation.dependencies.forbidden
      delivery.merge
    ].freeze
    COORDINATION_TOOL_NAMES = %w[
      repository_register
      change_set_create
      work_item_create
      work_item_dependency_declare
      change_set_activate
      work_item_acquire
      work_item_complete
      attempt_abandon
      write_set_reserve
      write_set_expand
      lease_renew
      lease_release
      guidance_record
      decision_interpretation_propose
      decision_interpretation_adjudicate
      decision_activate
      decision_correct
      agent_choice_record
      candidate_submit
      candidate_impact_surface_submit
      verification_obligation_claim
      compatibility_assessment_submit
      verification_obligation_waive
      merge_snapshot_register
      merge_verification_submit
      merge_authorization_request
      merge_observation_record
      release_set_prepare
      release_repository_integration_record
      release_verification_record
      release_activation_record
      release_compensation_complete
      skill_publish
      skill_publish_batch
      development_artifact_capture
      development_artifact_capture_batch
      development_artifact_relation_declare
      development_artifact_relation_declare_batch
      operation_batch_cancel
    ].freeze

    Identifier = String.constrained(format: IDENTIFIER_PATTERN)
    RepositoryId = String.constrained(format: REPOSITORY_ID_PATTERN)
    GitOid = String.constrained(format: GIT_OID_PATTERN)
    GitObjectFormat = String.enum(*GIT_OBJECT_FORMATS)
    GuidanceSource = String.enum(*GUIDANCE_SOURCES)
    Sha256Digest = String.constrained(format: SHA256_DIGEST_PATTERN)
    Timestamp = String.constrained(format: TIMESTAMP_PATTERN)
    UuidV7 = String.constrained(format: UUID_V7_PATTERN)
    TaskId = UuidV7
    ResourcePath = String.constrained(format: RESOURCE_PATH_PATTERN)
    ResourceKind = String.enum("file")
    ResourceKeyPolicyVersion = String.enum(*RESOURCE_KEY_POLICY_VERSIONS)
    LeaseMode = String.enum("exclusive")
    LeaseDurationSeconds = Integer.constrained(gteq: 30, lteq: 3_600)
    WriteSetSize = Integer.constrained(gteq: 1, lteq: 32)
    ExpandedWriteSetSize = Integer.constrained(gteq: 2, lteq: 32)
    FencingToken = Integer.constrained(gteq: 1)
    CoordinationToolName = String.enum(*COORDINATION_TOOL_NAMES)
    SkillId = String.constrained(format: SKILL_ID_PATTERN)
    SkillName = String.constrained(min_size: 1, max_size: SKILL_NAME_MAXIMUM_BYTES)
    SkillScope = String.constrained(min_size: 1, max_size: SKILL_SCOPE_MAXIMUM_BYTES)
    SkillDescription = String.constrained(max_size: SKILL_DESCRIPTION_MAXIMUM_BYTES)
    SkillInstructions = String.constrained(min_size: 1, max_size: SKILL_INSTRUCTIONS_MAXIMUM_BYTES)
    SkillRevision = Integer.constrained(gteq: 1)
    SkillExpectedRevision = Integer.constrained(gteq: 0)
    SkillAssetPath = String.constrained(min_size: 1, max_size: SKILL_ASSET_PATH_MAXIMUM_BYTES)
    SkillAssetMediaType = String.constrained(format: SKILL_MEDIA_TYPE_PATTERN)
    SkillAssetContentBase64 = String.constrained(max_size: SKILL_ASSET_BASE64_MAXIMUM_BYTES)
    SkillAssetByteSize = Integer.constrained(gteq: 0, lteq: SKILL_ASSET_MAXIMUM_BYTES)
    DevelopmentArtifactId = String.constrained(format: DEVELOPMENT_ARTIFACT_ID_PATTERN)
    DevelopmentArtifactRelationId = String.constrained(format: DEVELOPMENT_ARTIFACT_RELATION_ID_PATTERN)
    DevelopmentArtifactScope = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_SCOPE_MAXIMUM_BYTES
    )
    DevelopmentArtifactTitle = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_TITLE_MAXIMUM_BYTES
    )
    DevelopmentArtifactKind = String.enum(*DEVELOPMENT_ARTIFACT_KINDS)
    DevelopmentArtifactLabel = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_BYTES
    )
    DevelopmentArtifactLabels = Array.of(DevelopmentArtifactLabel).constrained(
      max_size: DEVELOPMENT_ARTIFACT_LABEL_MAXIMUM_COUNT
    )
    DevelopmentArtifactEncoding = String.enum("utf-8", "binary")
    DevelopmentArtifactMediaType = String.constrained(format: SKILL_MEDIA_TYPE_PATTERN)
    DevelopmentArtifactContentBase64 = String.constrained(
      max_size: DEVELOPMENT_ARTIFACT_CONTENT_BASE64_MAXIMUM_BYTES
    )
    DevelopmentArtifactByteSize = Integer.constrained(
      gteq: 0,
      lteq: DEVELOPMENT_ARTIFACT_CONTENT_MAXIMUM_BYTES
    )
    DevelopmentArtifactSourceKind = String.enum(*DEVELOPMENT_ARTIFACT_SOURCE_KINDS)
    DevelopmentArtifactSourceLocator = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_SOURCE_LOCATOR_MAXIMUM_BYTES
    )
    DevelopmentArtifactSourceRevision = String.constrained(
      max_size: DEVELOPMENT_ARTIFACT_SOURCE_REVISION_MAXIMUM_BYTES
    )
    DevelopmentArtifactCollector = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_COLLECTOR_MAXIMUM_BYTES
    )
    DevelopmentArtifactRelationKind = String.enum(*DEVELOPMENT_ARTIFACT_RELATION_KINDS)
    DevelopmentArtifactTargetKind = String.enum(*DEVELOPMENT_ARTIFACT_TARGET_KINDS)
    DevelopmentArtifactTargetId = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_TARGET_ID_MAXIMUM_BYTES
    )
    DevelopmentArtifactRelationPath = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_RELATION_PATH_MAXIMUM_BYTES
    )
    DevelopmentArtifactRelationFragment = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_RELATION_FRAGMENT_MAXIMUM_BYTES
    )
    DevelopmentArtifactRelationSupersessionReason = String.constrained(
      min_size: 1,
      max_size: DEVELOPMENT_ARTIFACT_RELATION_SUPERSESSION_REASON_MAXIMUM_BYTES
    )
    OperationBatchId = UuidV7
    OperationBatchItemIndex = Integer.constrained(gteq: 0, lt: OPERATION_BATCH_MAXIMUM_ITEMS)
    OperationBatchTotal = Integer.constrained(gteq: 1, lteq: OPERATION_BATCH_MAXIMUM_ITEMS)
    OperationBatchPageSize = Integer.constrained(eql: OPERATION_BATCH_PAGE_SIZE)
    OperationBatchEncodedByteSize = Integer.constrained(
      gteq: 1,
      lteq: OPERATION_BATCH_MAXIMUM_ENCODED_BYTES
    )
    OperationBatchTargetTool = String.enum(
      "skill_publish",
      "development_artifact_capture",
      "development_artifact_relation_declare"
    )
    OperationBatchOutcomeStatus = String.enum("succeeded", "rejected")
    OperationBatchStatus = String.enum("running", "completed", "completed_with_errors", "cancelled")
    Marker = String.constrained(min_size: 1, max_size: 512)
    MarkerPurpose = String.constrained(format: MARKER_PURPOSE_PATTERN)
    MarkerComponent = String.constrained(format: MARKER_COMPONENT_PATTERN)
    MarkerComponents = Array.of(MarkerComponent).constrained(min_size: 2, max_size: 32)
    ActorKind = String.enum(*ACTOR_KINDS)
    DependencyKind = String.enum(*DEPENDENCY_KINDS)
    WorkItemOutputKind = String.enum(*WORK_ITEM_OUTPUT_KINDS)
    DependencyRequiredOutputKind = String.enum(*DEPENDENCY_REQUIRED_OUTPUT_KINDS)
    Goal = String.constrained(min_size: 1, max_size: 4_000)
    GuidanceText = String.constrained(min_size: 1, max_size: 16_000)
    Criterion = String.constrained(min_size: 1, max_size: 2_000)
    AcceptanceCriteria = Array.of(Criterion).constrained(min_size: 1, max_size: 100)
    WorkItemAcceptanceCriteria = Array.of(Criterion).constrained(min_size: 1, max_size: 50)
    StateAcceptanceCriteria = Array.of(Criterion).constrained(max_size: 100)
    WorkItemStateAcceptanceCriteria = Array.of(Criterion).constrained(max_size: 50)
    WorkItemIds = Array.of(Identifier).constrained(max_size: 100)
    ReadinessWorkItemIds = Array.of(Identifier).constrained(min_size: 1, max_size: 100)
    GuidanceRepositoryIds = Array.of(RepositoryId).constrained(max_size: 100)
    EvidencePolicyStatus = String.enum("evidence_only")
    InterpretationPolicyStatus = String.enum("proposal_only")
    StatementKind = String.enum(*STATEMENT_KINDS)
    DecisionEffect = String.enum(*DECISION_EFFECTS)
    DecisionModality = String.enum(*DECISION_MODALITIES)
    DecisionValueSchema = String.enum(*DECISION_VALUE_SCHEMAS)
    InterpretationAssessmentStatus = String.enum(*INTERPRETATION_ASSESSMENT_STATUSES)
    InterpretationAdjudicationAction = String.enum(*INTERPRETATION_ADJUDICATION_ACTIONS)
    InterpretationClarificationStatus = String.enum(*INTERPRETATION_CLARIFICATION_STATUSES)
    InterpretationClarificationOrigin = String.enum(*INTERPRETATION_CLARIFICATION_ORIGINS)
    InterpretationLifecycleStatus = String.enum(*INTERPRETATION_LIFECYCLE_STATUSES)
    InterpretationAdjudicationOutcome = String.enum(*INTERPRETATION_ADJUDICATION_OUTCOMES)
    DecisionActivationOutcome = String.enum(*DECISION_ACTIVATION_OUTCOMES)
    DecisionCorrectionOutcome = String.enum(*DECISION_CORRECTION_OUTCOMES)
    DecisionPolicyStatus = String.enum(*DECISION_POLICY_STATUSES)
    DecisionPartitionAnchorKind = String.enum(*DECISION_PARTITION_ANCHOR_KINDS)
    DecisionChangeKind = String.enum(*DECISION_CHANGE_KINDS)
    AgentChoiceType = String.enum(*AGENT_CHOICE_TYPES)
    AgentChoiceAssessmentBasis = String.enum(*AGENT_CHOICE_ASSESSMENT_BASES)
    AgentChoicePolicyEvaluationStatus = String.enum(*AGENT_CHOICE_POLICY_EVALUATION_STATUSES)
    AgentChoicePolicyEvaluationBasis = String.enum(*AGENT_CHOICE_POLICY_EVALUATION_BASES)
    AgentChoicePolicyReasonCode = String.enum(*AGENT_CHOICE_POLICY_REASON_CODES)
    AgentChoiceOutcome = String.enum(*AGENT_CHOICE_OUTCOMES)
    AgentChoiceObservationStatus = String.enum(*AGENT_CHOICE_OBSERVATION_STATUSES)
    AgentChoiceImpactPolicyVersion = String.enum(*AGENT_CHOICE_IMPACT_POLICY_VERSIONS)
    AgentChoiceImpactScanStatus = String.enum(*AGENT_CHOICE_IMPACT_SCAN_STATUSES)
    AgentChoiceImpactScanSkipReason = String.enum(*AGENT_CHOICE_IMPACT_SCAN_SKIP_REASONS)
    AgentChoiceImpactAssessmentOutcome = String.enum(*AGENT_CHOICE_IMPACT_ASSESSMENT_OUTCOMES)
    AgentChoiceImpactAssessmentReason = String.enum(*AGENT_CHOICE_IMPACT_ASSESSMENT_REASONS)
    AgentChoiceInvalidationReason = String.enum(*AGENT_CHOICE_INVALIDATION_REASONS)
    CandidateCheckpointKind = String.enum(*CANDIDATE_CHECKPOINT_KINDS)
    CandidateManifestStatus = String.enum(*CANDIDATE_MANIFEST_STATUSES)
    CandidateGitFileMode = String.enum(*CANDIDATE_GIT_FILE_MODES)
    CandidateBuildInputKind = String.enum(*CANDIDATE_BUILD_INPUT_KINDS)
    CandidateEvidenceStatus = String.enum(*CANDIDATE_EVIDENCE_STATUSES)
    CandidateImpactKey = String.constrained(
      format: CANDIDATE_IMPACT_KEY_PATTERN,
      min_size: 3,
      max_size: 200
    )
    CandidateImpactValue = String.constrained(min_size: 1, max_size: 500)
    CandidateAnalyzerVersion = String.constrained(min_size: 1, max_size: 100)
    CandidateImpactQueryDirection = String.enum(*CANDIDATE_IMPACT_QUERY_DIRECTIONS)
    CandidateImpactRelationshipKind = String.enum(*CANDIDATE_IMPACT_RELATIONSHIP_KINDS)
    CandidateImpactReasonKind = String.enum(*CANDIDATE_IMPACT_REASON_KINDS)
    CandidateImpactIndexRole = String.enum(*CANDIDATE_IMPACT_INDEX_ROLES)
    CandidateImpactIndexKind = String.enum(*CANDIDATE_IMPACT_INDEX_KINDS)
    CandidateImpactIndexBucket = String.enum(*CANDIDATE_IMPACT_INDEX_BUCKETS)
    CandidateImpactPolicyEnforcementLevel = String.enum(*CANDIDATE_IMPACT_POLICY_ENFORCEMENT_LEVELS)
    CandidateImpactRequiredEvidenceKind = String.enum(*CANDIDATE_IMPACT_REQUIRED_EVIDENCE_KINDS)
    CandidateImpactRequiredEvidenceKinds = Array.of(CandidateImpactRequiredEvidenceKind)
      .constrained(min_size: 1, max_size: 8)
    CandidateCompatibilityObligationRuleVersion = String.enum(*CANDIDATE_COMPATIBILITY_OBLIGATION_RULE_VERSIONS)
    CandidateImpactIndexPolicyVersion = String.enum(*CANDIDATE_IMPACT_INDEX_POLICY_VERSIONS)
    CandidateImpactRegistrySweepRuleVersion = String.enum(*CANDIDATE_IMPACT_REGISTRY_SWEEP_RULE_VERSIONS)
    CandidateImpactPairScanRuleVersion = String.enum(*CANDIDATE_IMPACT_PAIR_SCAN_RULE_VERSIONS)
    CandidateImpactScanRuleVersion = String.enum(
      *CANDIDATE_IMPACT_REGISTRY_SWEEP_RULE_VERSIONS,
      *CANDIDATE_IMPACT_PAIR_SCAN_RULE_VERSIONS
    )
    CandidateImpactScanStatus = String.enum(*CANDIDATE_IMPACT_SCAN_STATUSES)
    CandidateImpactRegistrySweepSkipReason = String.enum(*CANDIDATE_IMPACT_REGISTRY_SWEEP_SKIP_REASONS)
    CandidateImpactPairScanSkipReason = String.enum(*CANDIDATE_IMPACT_PAIR_SCAN_SKIP_REASONS)
    CandidateImpactScanPageSize = Integer.enum(50)
    CandidateImpactScanPageRegistrationCount = Integer.constrained(gteq: 0, lteq: 50)
    CandidateImpactPairScanMarkers = Array.of(Marker).constrained(max_size: 32)
    VerificationObligationKind = String.enum(*VERIFICATION_OBLIGATION_KINDS)
    VerificationObligationStatus = String.enum(*VERIFICATION_OBLIGATION_STATUSES)
    VerificationObligationClaimState = String.enum(*VERIFICATION_OBLIGATION_CLAIM_STATES)
    VerificationObligationWaiverReasonCode = String.enum(*VERIFICATION_OBLIGATION_WAIVER_REASON_CODES)
    VerificationObligationWaiverReasonSummary = String.constrained(min_size: 1, max_size: 2_000)
    VerificationObligationInvalidationRuleVersion = String.enum(
      *VERIFICATION_OBLIGATION_INVALIDATION_RULE_VERSIONS
    )
    VerificationObligationValidityScanStatus = String.enum(
      *VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATUSES
    )
    VerificationObligationValidityPageSize = Integer.enum(50)
    VerificationObligationValidityPageCount = Integer.constrained(gteq: 0, lteq: 50)
    VerificationEvidenceConclusion = String.enum(*VERIFICATION_EVIDENCE_CONCLUSIONS)
    VerificationEvidenceFindingSeverity = String.enum(*VERIFICATION_EVIDENCE_FINDING_SEVERITIES)
    VerificationEvidenceProducerName = String.constrained(min_size: 1, max_size: 100)
    VerificationEvidenceProducerVersion = String.constrained(min_size: 1, max_size: 100)
    VerificationEvidenceFindingCode = String.constrained(min_size: 1, max_size: 100)
    VerificationEvidenceFindingSummary = String.constrained(min_size: 1, max_size: 2_000)
    MergeSnapshotEvidenceStatus = String.enum(*MERGE_SNAPSHOT_EVIDENCE_STATUSES)
    MergeSnapshotRegistrationPolicyVersion = String.enum(
      *MERGE_SNAPSHOT_REGISTRATION_POLICY_VERSIONS
    )
    MergeSnapshotCandidateCount = Integer.constrained(
      gteq: 1,
      lteq: MERGE_SNAPSHOT_MAXIMUM_CANDIDATES
    )
    MergeSnapshotProducerName = String.constrained(min_size: 1, max_size: 100)
    MergeSnapshotProducerVersion = String.constrained(min_size: 1, max_size: 100)
    MergeSnapshotVerificationEvidenceKind = String.enum(
      *MERGE_SNAPSHOT_VERIFICATION_EVIDENCE_KINDS
    )
    MergeSnapshotVerificationPolicyVersion = String.enum(
      *MERGE_SNAPSHOT_VERIFICATION_POLICY_VERSIONS
    )
    MergeSnapshotVerificationStatus = String.enum(*MERGE_SNAPSHOT_VERIFICATION_STATUSES)
    MergeAuthorizationPolicyVersion = String.enum(*MERGE_AUTHORIZATION_POLICY_VERSIONS)
    MergeAuthorizationOutcome = String.enum(*MERGE_AUTHORIZATION_OUTCOMES)
    MergeAuthorizationPolicyStatus = String.enum(*MERGE_AUTHORIZATION_POLICY_STATUSES)
    MergeAuthorizationObligationStatus = String.enum(*MERGE_AUTHORIZATION_OBLIGATION_STATUSES)
    MergeAuthorizationReasonCode = String.enum(*MERGE_AUTHORIZATION_REASON_CODES)
    MergeAuthorizationRequiredEvidenceKinds = Array.of(CandidateImpactRequiredEvidenceKind)
      .constrained(max_size: 8)
    MergeObservationPolicyVersion = String.enum(*MERGE_OBSERVATION_POLICY_VERSIONS)
    ReleaseSetPreparationPolicyVersion = String.enum(*RELEASE_SET_PREPARATION_POLICY_VERSIONS)
    ReleaseSetMemberPosition = Integer.constrained(gteq: 1, lteq: RELEASE_SET_MAXIMUM_MEMBERS)
    ReleaseSetIntegrationPolicyVersion = String.enum(*RELEASE_SET_INTEGRATION_POLICY_VERSIONS)
    ReleaseSetVerificationPolicyVersion = String.enum(*RELEASE_SET_VERIFICATION_POLICY_VERSIONS)
    ReleaseSetActivationPolicyVersion = String.enum(*RELEASE_SET_ACTIVATION_POLICY_VERSIONS)
    ReleaseSetCompensationRuleVersion = String.enum(*RELEASE_SET_COMPENSATION_RULE_VERSIONS)
    ReleaseSetCompletionRuleVersion = String.enum(*RELEASE_SET_COMPLETION_RULE_VERSIONS)
    ReleaseSetIntegrationOutcome = String.enum(*RELEASE_SET_INTEGRATION_OUTCOMES)
    ReleaseSetVerificationOutcome = String.enum(*RELEASE_SET_VERIFICATION_OUTCOMES)
    ReleaseSetActivationPointKind = String.enum(*RELEASE_SET_ACTIVATION_POINT_KINDS)
    ReleaseSetCompensationAction = String.enum(*RELEASE_SET_COMPENSATION_ACTIONS)
    ReleaseSetCompensationTriggerKind = String.enum(*RELEASE_SET_COMPENSATION_TRIGGER_KINDS)
    ReleaseSetCompletionOutcome = String.enum(*RELEASE_SET_COMPLETION_OUTCOMES)
    ReleaseSetExternalReference = String.constrained(min_size: 1, max_size: 1_000)
    ReleaseSetIntegrationAttemptNumber = Integer.constrained(
      gteq: 1,
      lteq: RELEASE_SET_INTEGRATION_MAXIMUM_ATTEMPTS
    )
    ReleaseSetVerificationAttemptNumber = Integer.constrained(
      gteq: 1,
      lteq: RELEASE_SET_VERIFICATION_MAXIMUM_ATTEMPTS
    )
    ReleaseSetFailureCode = String.constrained(min_size: 1, max_size: 100)
    ReleaseSetEvidenceSummary = String.constrained(min_size: 1, max_size: 2_000)
    ReleaseSetFindingSeverity = String.enum("info", "warning", "error", "critical")
    CandidateObligationPolicyStatus = String.enum(*CANDIDATE_OBLIGATION_POLICY_STATUSES)
    CandidateObligationDecisionOutcome = String.enum(*CANDIDATE_OBLIGATION_DECISION_OUTCOMES)
    CandidateImpactReasonMatches = Array.of(String.constrained(min_size: 1, max_size: 1_024))
      .constrained(min_size: 1, max_size: 256)
    CandidateEvidenceRevision = Integer.enum(1)
    CandidateManifestSize = Integer.constrained(
      gteq: 1,
      lteq: CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT
    )
    CandidateBuildInputCount = Integer.constrained(gteq: 0, lteq: 64)
    CandidateEnvironmentCount = Integer.constrained(gteq: 0, lteq: 32)
    CandidateCollectorVersion = String.constrained(min_size: 1, max_size: 100)
    CandidateEnvironmentName = String.constrained(min_size: 1, max_size: 100)
    CandidateEnvironmentValue = String.constrained(min_size: 1, max_size: 500)
    CandidateTargetBranch = String.constrained(min_size: 1, max_size: 255)
    GlobalPosition = Integer.constrained(gteq: 0)
    AgentChoiceImpactPageSize = Integer.enum(50)
    AgentChoiceImpactPageChoiceCount = Integer.constrained(gteq: 0, lteq: 50)
    AgentChoiceImpactListLimit = Integer.constrained(gteq: 1, lteq: 100)
    DecisionActivationIneligibilityReason = String.enum(*DECISION_ACTIVATION_INELIGIBILITY_REASONS)
    DecisionActivationIneligibilityReasons = Array.of(DecisionActivationIneligibilityReason).constrained(min_size: 1, max_size: 10)
    DecisionCorrectionIneligibilityReason = String.enum(*DECISION_CORRECTION_INELIGIBILITY_REASONS)
    DecisionCorrectionIneligibilityReasons = Array.of(DecisionCorrectionIneligibilityReason).constrained(min_size: 1, max_size: 10)
    ScopeProvenanceKind = String.enum(*SCOPE_PROVENANCE_KINDS)
    ScopeAnchorLevel = String.enum(*SCOPE_ANCHOR_LEVELS)
    DecisionPhase = String.enum(*DECISION_PHASES)
    EnforcementLevel = String.enum(*ENFORCEMENT_LEVELS)
    RetroactivityKind = String.enum(*RETROACTIVITY_KINDS)
    ViolationAction = String.enum(*VIOLATION_ACTIONS)
    ResolutionStrategy = String.enum(*RESOLUTION_STRATEGIES)
    MergeTargetKind = String.enum(*MERGE_TARGET_KINDS)
    MergeAction = String.enum(*MERGE_ACTIONS)
    SupportedInterpretationTopic = String.enum(*SUPPORTED_INTERPRETATION_TOPICS)
    ClassifierConfidenceMillionths = Integer.constrained(gteq: 0, lteq: 1_000_000)
    SourceCharacterIndex = Integer.constrained(gteq: 0)
    InterpretationLabel = String.constrained(min_size: 1, max_size: 200)
    InterpretationDescription = String.constrained(min_size: 1, max_size: 500)
    InterpretationLabels = Array.of(InterpretationLabel).constrained(max_size: 100)
    InterpretationOptions = Array.of(InterpretationLabel).constrained(max_size: 10)
    DecisionIdentifiers = Array.of(Identifier).constrained(max_size: 20)
    ScopeIdentifiers = Array.of(Identifier).constrained(max_size: 100)
    ScopeRepositoryIds = Array.of(RepositoryId).constrained(max_size: 100)
    ScopePaths = Array.of(ResourcePath).constrained(max_size: 100)
    InterpretationReasons = Array.of(Identifier).constrained(max_size: 20)
    InterpretationPageLimit = Integer.constrained(gteq: 1, lteq: 100)
    StreamRevisionCursor = Integer.constrained(gteq: -1)
    StreamRevision = Integer.constrained(gteq: 0)
    DecisionPartitions = Integer.constrained(gteq: 1, lteq: 32)
  end
end
