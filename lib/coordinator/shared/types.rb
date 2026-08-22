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

    Identifier = String.constrained(format: IDENTIFIER_PATTERN)
    RepositoryId = String.constrained(format: REPOSITORY_ID_PATTERN)
    GitOid = String.constrained(format: GIT_OID_PATTERN)
    GitObjectFormat = String.enum(*GIT_OBJECT_FORMATS)
    Sha256Digest = String.constrained(format: SHA256_DIGEST_PATTERN)
    Timestamp = String.constrained(format: TIMESTAMP_PATTERN)
    UuidV7 = String.constrained(format: UUID_V7_PATTERN)
    TaskId = UuidV7
    ResourcePath = String.constrained(format: RESOURCE_PATH_PATTERN)
    ResourceKind = String.enum("file")
    LeaseMode = String.enum("exclusive")
    LeaseDurationSeconds = Integer.constrained(gteq: 30, lteq: 3_600)
    FencingToken = Integer.constrained(gteq: 1)
    Marker = String.constrained(min_size: 1, max_size: 512)
    MarkerPurpose = String.constrained(format: MARKER_PURPOSE_PATTERN)
    MarkerComponent = String.constrained(format: MARKER_COMPONENT_PATTERN)
    MarkerComponents = Array.of(MarkerComponent).constrained(min_size: 2, max_size: 32)
    ActorKind = String.enum(*ACTOR_KINDS)
    DependencyKind = String.enum(*DEPENDENCY_KINDS)
    Goal = String.constrained(min_size: 1, max_size: 4_000)
    Criterion = String.constrained(min_size: 1, max_size: 2_000)
    AcceptanceCriteria = Array.of(Criterion).constrained(min_size: 1, max_size: 100)
    WorkItemAcceptanceCriteria = Array.of(Criterion).constrained(min_size: 1, max_size: 50)
    StateAcceptanceCriteria = Array.of(Criterion).constrained(max_size: 100)
    WorkItemStateAcceptanceCriteria = Array.of(Criterion).constrained(max_size: 50)
    WorkItemIds = Array.of(Identifier).constrained(max_size: 100)
    ReadinessWorkItemIds = Array.of(Identifier).constrained(min_size: 1, max_size: 100)
  end
end
