# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Expand do
  subject(:expand) { described_class.new }

  let(:preparer) { Coordinator::Write::Operations::PrepareExpandWriteSet.new }
  let(:command) do
    preparer.call(
      command_id: "cmd-lse-expand-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: lease_set_id,
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: requested_resources
    ).value!
  end
  let(:lease_set_id) { "03919191-9191-7191-8191-919191919191" }
  let(:expires_at) { "2026-08-22T10:15:00.000000Z" }
  let(:expanded_at) { "2026-08-22T10:02:00.000000Z" }
  let(:existing_resource) { normalized_resource("app/models/a.rb", base_blob_oid: "b" * 40) }
  let(:requested_resources) do
    [
      { kind: "file", path: existing_resource.path, base_blob_oid: existing_resource.base_blob_oid },
      { kind: "file", path: "app/models/b.rb", base_blob_oid: "c" * 40 }
    ]
  end
  let(:existing_reference) do
    Coordinator::Write::LeaseReferenceV1.new(
      lease_id: "01919191-9191-7191-8191-919191919191",
      resource_key: existing_resource.resource_key,
      resource_key_hash: existing_resource.resource_key_hash,
      resource_kind: existing_resource.kind,
      resource_path: existing_resource.path,
      base_blob_oid: existing_resource.base_blob_oid,
      fencing_token: 1
    )
  end
  let(:attempt_state) do
    active_attempt_state.new(
      lease_set_id:,
      lease_repository_id: "billing",
      lease_policy_version: "coordinator-resource-key/v1",
      lease_resources: [ existing_reference ],
      lease_reserved_at: "2026-08-22T10:00:00.000000Z",
      lease_expires_at: expires_at
    )
  end
  let(:current_observations) do
    [
      Coordinator::Write::CurrentLeaseObservationV1.new(
        reference: existing_reference,
        state: lease_state(existing_reference)
      )
    ]
  end
  let(:requested_observations) do
    command.resources.map.with_index do |resource, index|
      Coordinator::Write::RequestedLeaseObservationV1.new(
        prepared_resource: Coordinator::Write::PreparedLeaseResourceV1.new(
          resource:,
          lease_id: format("%08d-9191-7191-8191-919191919191", index + 4),
          event_id: format("%08d-9191-7191-8191-919191919191", index + 6)
        ),
        state: resource.resource_key_hash == existing_resource.resource_key_hash ?
          lease_state(existing_reference) : Coordinator::Write::Domain::ResourceLeases::State.initial
      )
    end
  end

  it "Given one current member and one free resource, when expanding, then preserves the set and deadline" do
    result = expand.call(
      attempt_state:,
      current_observations:,
      requested_observations:,
      command:,
      expanded_at:
    )

    expect(result).to be_success
    acquisition, expansion = result.value!.events
    expect(acquisition).to be_a(Coordinator::Write::Events::ResourceLeaseAcquiredV1)
    expect(acquisition.to_h).to include(
      lease_set_id:,
      attempt_id: "A-LSE-A",
      fencing_token: 1,
      acquired_at: expanded_at,
      expires_at:
    )
    expect(expansion).to be_a(Coordinator::Write::Events::WriteSetExpandedV1)
    expect(expansion.to_h).to include(
      lease_set_id:,
      added_resources: [ lease_reference(acquisition).to_h ],
      resource_count: 2,
      expanded_at:,
      expires_at:
    )
  end

  it "Given only matching existing members, when expanding, then emits no facts" do
    result = expand.call(
      attempt_state:,
      current_observations:,
      requested_observations: [ requested_observations.first ],
      command: command.new(resources: [ command.resources.first ]),
      expanded_at:
    )

    expect(result.failure.code).to eq(:write_set_unchanged)
  end

  it "Given different evidence for an existing identity, when expanding, then rejects the command" do
    conflicting_command = command.new(
      resources: [ command.resources.first.new(base_blob_oid: "d" * 40) ]
    )
    conflicting_observation = requested_observations.first.new(
      prepared_resource: requested_observations.first.prepared_resource.new(
        resource: conflicting_command.resources.first
      )
    )

    result = expand.call(
      attempt_state:,
      current_observations:,
      requested_observations: [ conflicting_observation ],
      command: conflicting_command,
      expanded_at:
    )

    expect(result.failure.code).to eq(:resource_evidence_conflict)
  end

  it "Given a referenced lease was superseded, when expanding, then reports the set is not current" do
    superseding_reference = existing_reference.new(
      lease_id: "08919191-9191-7191-8191-919191919191",
      fencing_token: 2
    )
    observations = [ current_observations.first.new(state: lease_state(superseding_reference)) ]

    result = expand.call(
      attempt_state:,
      current_observations: observations,
      requested_observations: requested_observations.last(1),
      command: command.new(resources: command.resources.last(1)),
      expanded_at:
    )

    expect(result.failure.code).to eq(:lease_set_not_current)
    expect(result.failure.details).to include(
      expected_lease_id: existing_reference.lease_id,
      current_lease_id: superseding_reference.lease_id,
      expected_fencing_token: 1,
      current_fencing_token: 2
    )
  end

  it "Given the common deadline equals decision time, when expanding, then reports expiry" do
    result = expand.call(
      attempt_state: attempt_state.new(lease_expires_at: expanded_at),
      current_observations:,
      requested_observations: requested_observations.last(1),
      command: command.new(resources: command.resources.last(1)),
      expanded_at:
    )

    expect(result.failure.code).to eq(:lease_set_expired)
    expect(result.failure.details).to include(
      lease_id: existing_reference.lease_id,
      fencing_token: 1,
      expires_at: expanded_at
    )
  end

  private

  def active_attempt_state
    Coordinator::Write::Domain::Attempts::State.reduce(
      [
        Coordinator::Write::Events::AttemptAuthorizedV1.new(
          attempt_id: "A-LSE-A",
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          agent_id: "agent-a",
          base_snapshots: [
            Coordinator::Write::RepositorySnapshotV1.new(
              repository_id: "billing",
              object_format: "sha1",
              commit_oid: "a" * 40
            )
          ],
          authorized_at: "2026-08-22T10:00:00.000000Z"
        ),
        Coordinator::Write::Events::AttemptStartedV1.new(
          attempt_id: "A-LSE-A",
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          started_at: "2026-08-22T10:00:00.000000Z"
        )
      ]
    )
  end

  def normalized_resource(path, base_blob_oid: nil)
    Coordinator::Write::FileResourceNormalizer.new.call(
      repository_id: "billing",
      kind: "file",
      path:,
      base_blob_oid:
    ).value!
  end

  def lease_state(reference)
    resource = existing_resource
    Coordinator::Write::Domain::ResourceLeases::State.reduce(
      [
        Coordinator::Write::Events::ResourceLeaseAcquiredV1.new(
          lease_id: reference.lease_id,
          lease_set_id:,
          resource_key: resource.resource_key,
          resource_key_hash: resource.resource_key_hash,
          resource_kind: resource.kind,
          resource_path: resource.path,
          policy_version: resource.policy_version,
          mode: "exclusive",
          change_set_id: "CS-LSE",
          work_item_id: "W-LSE-A",
          attempt_id: "A-LSE-A",
          agent_id: "agent-a",
          repository_id: "billing",
          object_format: "sha1",
          base_commit_oid: "a" * 40,
          base_blob_oid: resource.base_blob_oid,
          fencing_token: reference.fencing_token,
          acquired_at: "2026-08-22T10:00:00.000000Z",
          expires_at:
        )
      ]
    )
  end

  def lease_reference(event)
    Coordinator::Write::LeaseReferenceV1.new(
      lease_id: event.lease_id,
      resource_key: event.resource_key,
      resource_key_hash: event.resource_key_hash,
      resource_kind: event.resource_kind,
      resource_path: event.resource_path,
      base_blob_oid: event.base_blob_oid,
      fencing_token: event.fencing_token
    )
  end
end
