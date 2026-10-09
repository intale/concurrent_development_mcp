# frozen_string_literal: true

module ResourceLeaseExamples
  REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID
  LEASE_SET_ID = "03919191-9191-7191-8191-919191919191"
  ACQUIRED_AT = "2026-08-22T10:00:00.000000Z"
  EXPIRES_AT = "2026-08-22T10:15:00.000000Z"

  module_function

  def resource(
    resource_id: "01919191-9191-7191-8191-919191919191",
    kind: "file",
    path: "app/models/a.rb",
    base_blob_oid: "b" * 40
  )
    Coordinator::Write::LeaseResourceV2.new(
      resource_id:,
      kind:,
      path:,
      base_blob_oid:,
      policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION
    )
  end

  def target(resource)
    Coordinator::Write::ResourceLeaseTargetV1.new(
      resource_id: resource.resource_id,
      base_blob_oid: resource.base_blob_oid
    )
  end

  def reference(
    resource: resource(),
    lease_id: "04919191-9191-7191-8191-919191919191",
    fencing_token: 1
  )
    Coordinator::Write::LeaseReferenceV2.new(
      lease_id:,
      resource_id: resource.resource_id,
      resource_kind: resource.kind,
      resource_path: resource.path,
      base_blob_oid: resource.base_blob_oid,
      fencing_token:
    )
  end

  def acquisition(
    resource: resource(),
    reference: reference(resource:),
    lease_set_id: LEASE_SET_ID,
    attempt_id: "A-LSE-A",
    agent_id: "agent-a",
    fencing_token: reference.fencing_token,
    acquired_at: ACQUIRED_AT,
    expires_at: EXPIRES_AT
  )
    Coordinator::Write::Events::ResourceLeaseAcquiredV2.new(
      lease_id: reference.lease_id,
      lease_set_id:,
      resource_id: resource.resource_id,
      resource_kind: resource.kind,
      resource_path: resource.path,
      policy_version: resource.policy_version,
      mode: "exclusive",
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id:,
      agent_id:,
      repository_id: REPOSITORY_ID,
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      base_blob_oid: resource.base_blob_oid,
      fencing_token:,
      acquired_at:,
      expires_at:
    )
  end

  def lease_state(**attributes)
    event = acquisition(**attributes)
    Coordinator::Write::Domain::ResourceLeases::State.reduce([ event ])
  end

  def active_attempt_state(
    lease_set_id: nil,
    lease_resources: [],
    lease_expires_at: nil,
    lease_released_at: nil,
    agent_id: "agent-a"
  )
    state = Coordinator::Write::Domain::Attempts::State.reduce(
      [
        Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id: "A-LSE-A"),
        Coordinator::Write::Events::AttemptAssignedToWorkItemV1.new(
          attempt_id: "A-LSE-A", change_set_id: "CS-LSE", work_item_id: "W-LSE-A"
        ),
        Coordinator::Write::Events::AttemptAssignedToAgentV1.new(attempt_id: "A-LSE-A", agent_id:),
        Coordinator::Write::Events::AttemptBaseSnapshotRecordedV1.new(
          attempt_id: "A-LSE-A", repository_id: REPOSITORY_ID, object_format: "sha1", commit_oid: "a" * 40
        ),
        Coordinator::Write::Events::AttemptStartedV2.new(attempt_id: "A-LSE-A")
      ]
    )
    return state unless lease_set_id

    state.new(
      lease_set_id:,
      lease_repository_id: REPOSITORY_ID,
      lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      lease_resources:,
      lease_reserved_at: ACQUIRED_AT,
      lease_expires_at:,
      lease_released_at:
    )
  end

  def actor
    Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a")
  end
end
