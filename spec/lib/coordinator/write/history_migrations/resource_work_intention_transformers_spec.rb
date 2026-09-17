# frozen_string_literal: true

RSpec.describe "history migration Resource and WorkIntention transformers", :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { SecureRandom.uuid_v7 }
  let(:work_item_id) { SecureRandom.uuid_v7 }
  let(:attempt_id) { SecureRandom.uuid_v7 }
  let(:lease_set_id) { SecureRandom.uuid_v7 }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-luna-a") }
  let(:system_actor) do
    Coordinator::Write::Commands::Actor.new(kind: "system", id: "resource-lease-maintenance")
  end
  let(:base_commit_oid) { "1" * 40 }
  let(:resources) do
    [
      lease_resource(path: "config/routes.rb", base_blob_oid: "2" * 40),
      lease_resource(path: "app/models/project.rb", base_blob_oid: "3" * 40),
      lease_resource(path: "spec/models/project_spec.rb", base_blob_oid: "4" * 40)
    ]
  end

  before do
    persist_planning_context(attempt_id:)
    resources.each { persist_resource_identity(_1) }
  end

  it "migrates Resource identity facts to a UUIDv7 stream without occurrence timestamps" do
    resource = resources.first
    identity_events = resource_identity_events(resource)
    unbound = persist_resource_unbound(resource, reason: "renamed")
    source_events = identity_events + [ unbound ]
    upper_position = source_events.last.global_position

    facts = source_events.map { transform(_1, upper_position:).value!.sole }
    target_stream = facts.first.target_stream

    expect(target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(target_stream.stream_id).not_to eq(resource.resource_id)
    expect(facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ResourceIdentityV2::Registered,
      Coordinator::Write::Events::ResourceIdentityV2::Bound,
      Coordinator::Write::Events::ResourceIdentityV2::Unbound
    ])
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(
      :registered_at,
      :bound_at,
      :unbound_at
    )
    expect(facts.flat_map(&:markers)).not_to include(a_string_matching(/sha(?:256)?/i))

    source_events.each { expect(plan(_1, upper_position:)).to be_success }
    source_events.each { expect(dispatch(_1, upper_position:)).to be_success }
    target_events = target_store.read(
      target_stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ResourceRegistered ResourceBound ResourceUnbound],
        maximum_count: 3,
        direction: :asc
      )
    )
    expect(target_events.map(&:type)).to eq(%w[ResourceRegistered ResourceBound ResourceUnbound])
    expect(target_events.map(&:stream_revision)).to eq([ 0, 1, 2 ])
  end

  it "turns an exclusive write-set lifecycle into cohesive work-intention histories" do
    lifecycle = persist_write_set_lifecycle
    upper_position = lifecycle.fetch(:ordered).last.global_position

    acquisition_facts = lifecycle.fetch(:acquisitions).map do |event|
      transform(event, upper_position:).value!.sole
    end
    reservation_facts = transform(lifecycle.fetch(:reservation), upper_position:).value!
    expansion_facts = transform(lifecycle.fetch(:expansion), upper_position:).value!
    renewal_facts = lifecycle.fetch(:renewals).map do |event|
      transform(event, upper_position:).value!.sole
    end
    release_facts = lifecycle.fetch(:releases).map do |event|
      transform(event, upper_position:).value!.sole
    end

    expect(reservation_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::WorkIntentionSetCreatedV1,
      Coordinator::Write::Events::WorkIntentionAddedToSetV1,
      Coordinator::Write::Events::WorkIntentionAddedToSetV1
    ])
    expect(expansion_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::WorkIntentionAddedToSetV1
    ])
    expect(acquisition_facts.map { _1.event.class }.uniq).to eq([
      Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1
    ])
    expect(renewal_facts.map { _1.event.class }.uniq).to eq([
      Coordinator::Write::Events::ResourceWorkIntentionRenewedV1
    ])
    expect(release_facts.map { _1.event.class }.uniq).to eq([
      Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1
    ])
    expect(transform(lifecycle.fetch(:set_renewal), upper_position:).value!).to be_empty
    expect(transform(lifecycle.fetch(:set_release), upper_position:).value!).to be_empty

    declarations = acquisition_facts.map(&:event)
    expect(declarations.map(&:intention_id)).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(declarations.map(&:intention_id)).not_to include(*lifecycle.fetch(:lease_ids))
    expect(declarations).to all(
      have_attributes(
        mode: "exclusive",
        purpose: Coordinator::Write::HistoryMigrations::WorkIntentionV1Transformer::LEGACY_PURPOSE,
        context: nil
      )
    )
    transformed_events = (
      acquisition_facts + reservation_facts + expansion_facts + renewal_facts + release_facts
    ).map(&:event)
    expect(transformed_events.flat_map { _1.to_h.keys }).not_to include(
      :acquired_at,
      :renewed_at,
      :previous_expires_at,
      :released_at,
      :resources,
      :resource_count
    )
    expect(
      (acquisition_facts + reservation_facts + expansion_facts + renewal_facts + release_facts)
        .flat_map(&:markers)
    ).not_to include(a_string_matching(/sha(?:256)?/i))

    lifecycle.fetch(:ordered).each do |event|
      expect(plan(event, upper_position:)).to be_success
    end
    lifecycle.fetch(:ordered).each do |event|
      expect(dispatch(event, upper_position:)).to be_success
    end
    expect(dispatch(lifecycle.fetch(:set_renewal), upper_position:).value!).to have_attributes(
      events: [],
      outcome: "skipped"
    )

    set_id = reservation_facts.first.event.set_id
    set_state = Coordinator::Write::WorkIntentionSetLoader.new(event_store: target_store).call(set_id)
    expect(set_state).to have_attributes(
      set_id:,
      repository_id: reservation_facts.first.event.repository_id
    )
    expect(set_state.members.length).to eq(3)
    intention_states = declarations.map do |declaration|
      Coordinator::Write::WorkIntentionLoader.new(event_store: target_store)
        .call(declaration.intention_id).state
    end
    expect(intention_states).to all(have_attributes(withdrawn: true, expired: false))
    expect(intention_states.map(&:expires_at).uniq).to eq([ timestamp(50) ])

    target_events = acquisition_facts.flat_map do |fact|
      target_store.read_grouped(
        fact.target_stream,
        Coordinator::Write::EventQueries::WORK_INTENTION_STATE
      )
    end
    expect(target_events.map(&:correlation_id).uniq.length).to eq(4)
    reserve_targets = target_events.select do |event|
      declarations.map(&:intention_id).take(2).include?(event.stream.stream_id) &&
        event.type == "ResourceWorkIntentionDeclared"
    end
    set_targets = target_store.read(
      reservation_facts.first.target_stream,
      Coordinator::Write::EventQueries::WORK_INTENTION_SET_STATE
    )
    expect((reserve_targets + set_targets.take(3)).map(&:correlation_id).uniq.one?).to be(true)
  end

  it "maps expiry while discarding the legacy boundary snapshot dump" do
    expiry = persist_expired_lease
    boundary = persist_boundary_snapshot(expiry.fetch(:expiration))
    upper_position = boundary.global_position

    declaration = transform(expiry.fetch(:acquisition), upper_position:).value!.sole
    expiration = transform(expiry.fetch(:expiration), upper_position:).value!.sole
    discarded = transform(boundary, upper_position:).value!

    expect(expiration.event).to eq(
      Coordinator::Write::Events::ResourceWorkIntentionExpiredV1.new(
        intention_id: declaration.event.intention_id,
        resource_id: declaration.event.resource_id,
        fencing_token: 1,
        expires_at: timestamp(40)
      )
    )
    expect(expiration.event.to_h.keys).not_to include(:expired_at, :acquired_at, :renewed_at)
    expect(discarded).to be_empty

    (expiry.fetch(:ordered) + [ boundary ]).each do |event|
      expect(plan(event, upper_position:)).to be_success
    end
    expiry.fetch(:ordered).each do |event|
      expect(dispatch(event, upper_position:)).to be_success
    end
    expect(dispatch(boundary, upper_position:).value!).to have_attributes(events: [], outcome: "skipped")
    state = Coordinator::Write::WorkIntentionLoader.new(event_store: target_store)
      .call(declaration.event.intention_id).state
    expect(state).to have_attributes(expired: true, withdrawn: false)
  end

  it "fails closed when a write-set member disagrees with its acquisition" do
    resource = resources.first
    lease_id = SecureRandom.uuid_v7
    acquisition = lease_acquisition(
      resource,
      lease_id:,
      lease_set_id:,
      attempt_id:,
      acquired_at: timestamp(10),
      expires_at: timestamp(40)
    )
    persist_lease(acquisition, command_id: "legacy-corrupt-reserve", correlation_id: SecureRandom.uuid_v7)
    incorrect = Coordinator::Write::LeaseReferenceV2.new(
      reference_for(acquisition).to_h.merge(base_blob_oid: "f" * 40)
    )
    reservation = Coordinator::Write::Events::WriteSetReservedV2.new(
      lease_set_id:,
      change_set_id:,
      work_item_id:,
      attempt_id:,
      repository_id:,
      policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
      resources: [ incorrect ],
      reserved_at: timestamp(10),
      expires_at: timestamp(40)
    )
    event = persist_write_set(
      reservation,
      command_id: "legacy-corrupt-reserve",
      correlation_id: SecureRandom.uuid_v7
    )

    result = transform(event, upper_position: event.global_position)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "WriteSetReserved",
      schema_version: 2,
      source_event_id: event.id
    )
  end

  private

  def persist_planning_context(attempt_id:)
    persist(
      Coordinator::Write::Events::RepositoryRegisteredV1.new(
        repository_id:,
        scope: "project:history-migration",
        repository_key: "history-migration",
        display_name: "History migration",
        paths: [],
        remotes: [],
        registered_at: timestamp(0)
      ),
      stream: stream("DevelopmentPlanning", "Repository", repository_id),
      markers: [ "repository:#{repository_id}" ],
      command_id: "legacy-repository",
      actor:,
      policy_version: "repository/v1"
    )
    persist(
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id:,
        goal: "Migrate legacy work coordination",
        created_at: timestamp(1)
      ),
      stream: stream("DevelopmentPlanning", "ChangeSet", change_set_id),
      markers: [ "change-set:#{change_set_id}" ],
      command_id: "legacy-change-set",
      actor:,
      policy_version: "change-set/v1"
    )
    persist(
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id:,
        change_set_id:,
        repository_id:,
        goal: "Coordinate legacy writes",
        acceptance_criteria: [ "Preserve the modeled intention" ],
        competitive_mode: false,
        created_at: timestamp(2)
      ),
      stream: stream("DevelopmentExecution", "WorkItem", work_item_id),
      markers: [ "work-item:#{work_item_id}" ],
      command_id: "legacy-work-item",
      actor:,
      policy_version: "work-item/v1"
    )
    correlation_id = SecureRandom.uuid_v7
    persist(
      Coordinator::Write::Events::AttemptAuthorizedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        agent_id: actor.id,
        base_snapshots: [
          Coordinator::Write::RepositorySnapshotV1.new(
            repository_id:,
            object_format: "sha1",
            commit_oid: base_commit_oid
          )
        ],
        authorized_at: timestamp(3)
      ),
      stream: stream("DevelopmentExecution", "Attempt", attempt_id),
      markers: [ "attempt:#{attempt_id}" ],
      command_id: "legacy-attempt",
      actor:,
      policy_version: "attempt/v1",
      correlation_id:
    )
    persist(
      Coordinator::Write::Events::AttemptStartedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        started_at: timestamp(4)
      ),
      stream: stream("DevelopmentExecution", "Attempt", attempt_id),
      markers: [ "attempt:#{attempt_id}" ],
      command_id: "legacy-attempt",
      actor:,
      policy_version: "attempt/v1",
      correlation_id:
    )
  end

  def persist_resource_identity(resource)
    identity = resource_identity(resource)
    common = [
      identity.identity_marker,
      "resource:#{resource.resource_id}",
      "repository:#{repository_id}"
    ]
    registration = persist(
      Coordinator::Write::Events::ResourceIdentityV1::Registered.new(
        resource_id: resource.resource_id,
        repository_id:,
        kind: resource.kind,
        normalized_path: resource.path,
        registered_at: timestamp(5)
      ),
      stream: resource_stream(resource),
      markers: common,
      command_id: "legacy-resource-#{resource.resource_id}",
      actor:,
      policy_version: "resource-identity/v1"
    )
    binding = persist(
      Coordinator::Write::Events::ResourceIdentityV1::Bound.new(
        resource_id: resource.resource_id,
        repository_id:,
        kind: resource.kind,
        normalized_path: resource.path,
        bound_at: timestamp(6)
      ),
      stream: resource_stream(resource),
      markers: common + [ identity.current_path_marker ],
      command_id: "legacy-resource-#{resource.resource_id}",
      actor:,
      policy_version: "resource-identity/v1"
    )
    [ registration, binding ]
  end

  def resource_identity_events(resource)
    source_store.read(
      resource_stream(resource),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[ResourceRegistered ResourceBound],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def persist_resource_unbound(resource, reason:)
    identity = resource_identity(resource)
    persist(
      Coordinator::Write::Events::ResourceIdentityV1::Unbound.new(
        resource_id: resource.resource_id,
        repository_id:,
        kind: resource.kind,
        normalized_path: resource.path,
        reason:,
        unbound_at: timestamp(7)
      ),
      stream: resource_stream(resource),
      markers: [
        identity.identity_marker,
        identity.current_path_marker,
        "resource:#{resource.resource_id}",
        "repository:#{repository_id}"
      ],
      command_id: "legacy-unbind-#{resource.resource_id}",
      actor:,
      policy_version: "resource-identity/v1"
    )
  end

  def persist_write_set_lifecycle
    lease_ids = resources.map { SecureRandom.uuid_v7 }
    reserve_correlation = SecureRandom.uuid_v7
    initial_acquisitions = resources.take(2).each_with_index.map do |resource, index|
      persist_lease(
        lease_acquisition(
          resource,
          lease_id: lease_ids.fetch(index),
          lease_set_id:,
          attempt_id:,
          acquired_at: timestamp(10),
          expires_at: timestamp(40)
        ),
        command_id: "legacy-reserve",
        correlation_id: reserve_correlation
      )
    end
    reservation = persist_write_set(
      Coordinator::Write::Events::WriteSetReservedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        resources: initial_acquisitions.map { reference_for(load_source(_1)) },
        reserved_at: timestamp(10),
        expires_at: timestamp(40)
      ),
      command_id: "legacy-reserve",
      correlation_id: reserve_correlation
    )

    expansion_correlation = SecureRandom.uuid_v7
    added_acquisition = persist_lease(
      lease_acquisition(
        resources.fetch(2),
        lease_id: lease_ids.fetch(2),
        lease_set_id:,
        attempt_id:,
        acquired_at: timestamp(12),
        expires_at: timestamp(40)
      ),
      command_id: "legacy-expand",
      correlation_id: expansion_correlation
    )
    added_reference = reference_for(load_source(added_acquisition))
    expansion = persist_write_set(
      Coordinator::Write::Events::WriteSetExpandedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        added_resources: [ added_reference ],
        resource_count: 3,
        expanded_at: timestamp(12),
        expires_at: timestamp(40)
      ),
      command_id: "legacy-expand",
      correlation_id: expansion_correlation
    )

    acquisitions = initial_acquisitions + [ added_acquisition ]
    renewal_correlation = SecureRandom.uuid_v7
    renewals = acquisitions.map do |event|
      acquisition = load_source(event)
      persist_lease(
        lease_renewal(acquisition),
        command_id: "legacy-renew",
        correlation_id: renewal_correlation
      )
    end
    references = acquisitions.map { reference_for(load_source(_1)) }
    set_renewal = persist_write_set(
      Coordinator::Write::Events::WriteSetRenewedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        resources: references,
        resource_count: 3,
        renewed_at: timestamp(20),
        previous_expires_at: timestamp(40),
        expires_at: timestamp(50)
      ),
      command_id: "legacy-renew",
      correlation_id: renewal_correlation
    )

    release_correlation = SecureRandom.uuid_v7
    releases = acquisitions.map do |event|
      acquisition = load_source(event)
      persist_lease(
        lease_release(acquisition),
        command_id: "legacy-release",
        correlation_id: release_correlation
      )
    end
    set_release = persist_write_set(
      Coordinator::Write::Events::WriteSetReleasedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        resources: references,
        resource_count: 3,
        previous_expires_at: timestamp(50),
        released_at: timestamp(30)
      ),
      command_id: "legacy-release",
      correlation_id: release_correlation
    )

    {
      acquisitions:,
      reservation:,
      expansion:,
      renewals:,
      set_renewal:,
      releases:,
      set_release:,
      lease_ids:,
      ordered: [
        *initial_acquisitions,
        reservation,
        added_acquisition,
        expansion,
        *renewals,
        set_renewal,
        *releases,
        set_release
      ]
    }
  end

  def persist_expired_lease
    resource = resources.first
    lease_id = SecureRandom.uuid_v7
    correlation_id = SecureRandom.uuid_v7
    acquisition = persist_lease(
      lease_acquisition(
        resource,
        lease_id:,
        lease_set_id:,
        attempt_id:,
        acquired_at: timestamp(10),
        expires_at: timestamp(40)
      ),
      command_id: "legacy-expiry-reserve",
      correlation_id:
    )
    reservation = persist_write_set(
      Coordinator::Write::Events::WriteSetReservedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        resources: [ reference_for(load_source(acquisition)) ],
        reserved_at: timestamp(10),
        expires_at: timestamp(40)
      ),
      command_id: "legacy-expiry-reserve",
      correlation_id:
    )
    source = load_source(acquisition)
    expiration = persist_lease(
      Coordinator::Write::Events::ResourceLeaseExpiredV2.new(
        lease_id: source.lease_id,
        lease_set_id: source.lease_set_id,
        resource_id: source.resource_id,
        resource_kind: source.resource_kind,
        resource_path: source.resource_path,
        policy_version: source.policy_version,
        mode: source.mode,
        change_set_id: source.change_set_id,
        work_item_id: source.work_item_id,
        attempt_id: source.attempt_id,
        agent_id: source.agent_id,
        repository_id: source.repository_id,
        object_format: source.object_format,
        base_commit_oid: source.base_commit_oid,
        base_blob_oid: source.base_blob_oid,
        fencing_token: source.fencing_token,
        acquired_at: source.acquired_at,
        renewed_at: nil,
        expires_at: source.expires_at,
        expired_at: timestamp(41)
      ),
      command_id: "legacy-expire",
      correlation_id: SecureRandom.uuid_v7,
      actor: system_actor
    )
    { acquisition:, reservation:, expiration:, ordered: [ acquisition, reservation, expiration ] }
  end

  def persist_boundary_snapshot(caused_by)
    marker = "compound:resource-boundary-v2|legacy-sha256-selector"
    persist(
      Coordinator::Write::Events::ResourceBoundaryEpochRolledV2.new(
        repository_id:,
        boundary_marker: marker,
        epoch: 1,
        previous_through_global_position: nil,
        through_global_position: 0,
        active_leases: [],
        rolled_at: timestamp(42)
      ),
      stream: stream("DevelopmentCoordination", "ResourceBoundaryEpoch", repository_id),
      markers: [ marker, "command:legacy-boundary" ],
      command_id: "legacy-boundary",
      actor: system_actor,
      policy_version: "resource-boundary-maintenance/v2",
      correlation_id: caused_by.correlation_id
    )
  end

  def lease_acquisition(resource, lease_id:, lease_set_id:, attempt_id:, acquired_at:, expires_at:)
    Coordinator::Write::Events::ResourceLeaseAcquiredV2.new(
      lease_id:,
      lease_set_id:,
      resource_id: resource.resource_id,
      resource_kind: resource.kind,
      resource_path: resource.path,
      policy_version: resource.policy_version,
      mode: "exclusive",
      change_set_id:,
      work_item_id:,
      attempt_id:,
      agent_id: actor.id,
      repository_id:,
      object_format: "sha1",
      base_commit_oid:,
      base_blob_oid: resource.base_blob_oid,
      fencing_token: 1,
      acquired_at:,
      expires_at:
    )
  end

  def lease_renewal(acquisition)
    Coordinator::Write::Events::ResourceLeaseRenewedV2.new(
      **acquisition.to_h.except(:acquired_at, :expires_at),
      renewed_at: timestamp(20),
      previous_expires_at: timestamp(40),
      expires_at: timestamp(50)
    )
  end

  def lease_release(acquisition)
    Coordinator::Write::Events::ResourceLeaseReleasedV2.new(
      **acquisition.to_h.except(:expires_at),
      previous_expires_at: timestamp(50),
      released_at: timestamp(30)
    )
  end

  def persist_lease(payload, command_id:, correlation_id:, actor: self.actor)
    persist(
      payload,
      stream: stream("DevelopmentCoordination", "ResourceLease", payload.resource_id),
      markers: common_write_markers(payload, command_id:) + [
        "resource:#{payload.resource_id}",
        "resource-kind:#{payload.resource_kind}"
      ],
      command_id:,
      actor:,
      policy_version: payload.policy_version,
      correlation_id:
    )
  end

  def persist_write_set(payload, command_id:, correlation_id:)
    persist(
      payload,
      stream: stream("DevelopmentExecution", "Attempt", payload.attempt_id),
      markers: common_write_markers(payload, command_id:),
      command_id:,
      actor:,
      policy_version: payload.policy_version,
      correlation_id:
    )
  end

  def common_write_markers(payload, command_id:)
    [
      "change-set:#{payload.change_set_id}",
      "work-item:#{payload.work_item_id}",
      "attempt:#{payload.attempt_id}",
      "command:#{command_id}",
      "lease-set:#{payload.lease_set_id}",
      "repository:#{payload.repository_id}"
    ]
  end

  def reference_for(lease)
    Coordinator::Write::LeaseReferenceV2.new(
      lease_id: lease.lease_id,
      resource_id: lease.resource_id,
      resource_kind: lease.resource_kind,
      resource_path: lease.resource_path,
      base_blob_oid: lease.base_blob_oid,
      fencing_token: lease.fencing_token
    )
  end

  def lease_resource(path:, base_blob_oid:)
    Coordinator::Write::LeaseResourceV2.new(
      resource_id: SecureRandom.uuid_v7,
      kind: "file",
      path:,
      base_blob_oid:,
      policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION
    )
  end

  def resource_identity(resource)
    Coordinator::Write::ResourceIdentityNormalizer.new.call(
      repository_id:,
      kind: resource.kind,
      path: resource.path
    ).value!
  end

  def resource_stream(resource)
    stream("DevelopmentCoordination", "Resource", resource.resource_id)
  end

  def stream(context, name, id)
    Coordinator::Write::StreamReference.new(
      context:,
      stream_name: name,
      stream_id: id
    )
  end

  def persist(
    payload,
    stream:,
    markers:,
    command_id:,
    actor:,
    policy_version:,
    correlation_id: SecureRandom.uuid_v7
  )
    source_store.append(
      stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: payload.class.event_type,
          data: payload.to_h,
          metadata: {
            "schema_version" => payload.class.schema_version,
            "command_id" => command_id,
            "actor_kind" => actor.kind,
            "actor_id" => actor.id,
            "recorded_by" => "coordinator",
            "policy_version" => policy_version
          },
          markers:,
          correlation_id:
        )
      ]
    ).sole
  end

  def load_source(event)
    Coordinator::Write::HistoryMigrations::LegacyEventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def dispatch(source_event, upper_position:)
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
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

  def timestamp(minute)
    format("2026-08-01T10:%02d:00.000000Z", minute)
  end
end
