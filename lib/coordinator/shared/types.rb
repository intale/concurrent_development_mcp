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
    MARKER_PURPOSE_PATTERN = /\A[a-z][a-z0-9-]{0,63}\z/
    MARKER_COMPONENT_PATTERN = /\A(?!compound:)[^\u0000\r\n]{1,512}\z/

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
    AGENT_CHOICE_OBSERVATION_STATUSES = %w[recorded accepted].freeze
    AGENT_CHOICE_IMPACT_POLICY_VERSIONS = %w[agent-choice-decision-impact/v1].freeze
    AGENT_CHOICE_IMPACT_SCAN_STATUSES = %w[absent running skipped completed].freeze
    AGENT_CHOICE_IMPACT_SCAN_SKIP_REASONS = %w[future_only candidate_scope artifact_scope].freeze
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
      testing.framework
      testing.required_suites
      implementation.dependencies.forbidden
      delivery.merge
    ].freeze
    COORDINATION_TOOL_NAMES = %w[
      change_set_create
      work_item_create
      work_item_dependency_declare
      change_set_activate
      work_item_acquire
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
    LeaseMode = String.enum("exclusive")
    LeaseDurationSeconds = Integer.constrained(gteq: 30, lteq: 3_600)
    WriteSetSize = Integer.constrained(gteq: 1, lteq: 32)
    ExpandedWriteSetSize = Integer.constrained(gteq: 2, lteq: 32)
    FencingToken = Integer.constrained(gteq: 1)
    CoordinationToolName = String.enum(*COORDINATION_TOOL_NAMES)
    Marker = String.constrained(min_size: 1, max_size: 512)
    MarkerPurpose = String.constrained(format: MARKER_PURPOSE_PATTERN)
    MarkerComponent = String.constrained(format: MARKER_COMPONENT_PATTERN)
    MarkerComponents = Array.of(MarkerComponent).constrained(min_size: 2, max_size: 32)
    ActorKind = String.enum(*ACTOR_KINDS)
    DependencyKind = String.enum(*DEPENDENCY_KINDS)
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
    GlobalPosition = Integer.constrained(gteq: 0)
    AgentChoiceImpactPageSize = Integer.enum(50)
    AgentChoiceImpactPageChoiceCount = Integer.constrained(gteq: 0, lteq: 50)
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
