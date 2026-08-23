# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CoordContextV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:projector) { described_class.new }

  it "atomically projects exact source identities and ignores duplicate delivery" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    change_set_events = change_set_events("CS-100")
    work_item_event = work_item_events("W-100").sole

    change_set_events.first(2).each { projector.call(_1) }
    projector.call(change_set_events.find { _1.type == "WorkItemAddedToChangeSet" })
    projector.call(work_item_event)
    projector.call(work_item_event)

    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "work_item",
      scope_id: "W-100"
    )
    expect(snapshot.state.change_set.to_h).to include(
      change_set_id: "CS-100",
      goal: "Coordinate CS-100",
      acceptance_criteria: [ "Agents do not overlap" ]
    )
    expect(snapshot.state.work_item_ids).to eq([ "W-100" ])
    expect(snapshot.state.work_items.sole.to_h).to include(
      work_item_id: "W-100",
      repository_id: "billing",
      status: "planned"
    )
    expect(snapshot.source_positions.length).to eq(2)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "coord_context").count).to eq(4)
  end

  it "converges when cross-stream WorkItem siblings arrive in either order" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    change_set_events("CS-100").first(2).each { projector.call(_1) }

    membership = change_set_events("CS-100").find { _1.type == "WorkItemAddedToChangeSet" }
    details = work_item_events("W-100").sole
    projector.call(membership)
    projector.call(details)
    first_document = Coordinator::Read::CoordContext.find("CS-100").document

    ReadModelTestSafety.clean!
    change_set_events("CS-100").first(2).each { projector.call(_1) }
    projector.call(details)
    projector.call(membership)

    expect(Coordinator::Read::CoordContext.find("CS-100").document).to eq(first_document)
  end

  it "projects activation, ownership, exact Attempt bases, and observed write-set evidence" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "activate-CS-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-100"
    ).value!
    activation = change_set_events("CS-100").find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "acquire-W-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      base_snapshots: [
        { repository_id: "billing", commit_oid: "a" * 40 }
      ]
    ).value!
    reservation = Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "reserve-A-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [
        { kind: "file", path: "app/models/invoice.rb", base_blob_oid: "b" * 40 },
        { kind: "file", path: "db/schema.rb" }
      ],
      lease_duration_seconds: 300
    ).value!.data
    expansion = Coordinator::Write::Operations::ExecuteExpandWriteSet.new(event_store:).call(
      command_id: "expand-A-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      lease_set_id: reservation.lease_set_id,
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [
        { kind: "file", path: "app/models/invoice.rb", base_blob_oid: "b" * 40 },
        { kind: "file", path: "app/services/tax.rb", base_blob_oid: "c" * 40 }
      ]
    ).value!.data
    renewal = Coordinator::Write::Operations::ExecuteRenewLeaseSet.new(event_store:).call(
      command_id: "renew-A-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      lease_set_id: reservation.lease_set_id,
      leases: (reservation.resources + expansion.added_resources).map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end,
      lease_duration_seconds: 600
    ).value!.data
    release = Coordinator::Write::Operations::ExecuteReleaseLeaseSet.new(event_store:).call(
      command_id: "release-A-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      lease_set_id: reservation.lease_set_id,
      leases: (reservation.resources + expansion.added_resources).map do |reference|
        {
          resource_key_hash: reference.resource_key_hash,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end
    ).value!.data

    planning = change_set_events("CS-100")
    work = work_item_events("W-100")
    attempt = event_store.read(
      streams.attempt("A-100"),
      Coordinator::Write::EventQueries::ATTEMPT_FOR_WRITE_SET_EXPANSION
    ) + event_store.read(
      streams.attempt("A-100"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WriteSetRenewed", "WriteSetReleased" ],
        maximum_count: 2,
        direction: :asc
      )
    )
    [ planning[0], planning[1], work[0], planning[2], planning[3], work[1], work[2], *attempt ].each do |event|
      projector.call(event)
    end

    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "attempt",
      scope_id: "A-100"
    )
    expect(snapshot.state.change_set.status).to eq("active")
    expect(snapshot.state.work_items.sole.to_h).to include(
      status: "acquired",
      active_attempt_id: "A-100",
      active_agent_id: "agent-1"
    )
    expect(snapshot.state.attempts.sole.to_h).to include(
      attempt_id: "A-100",
      status: "started",
      base_snapshots: [
        { repository_id: "billing", object_format: "sha1", commit_oid: "a" * 40 }
      ]
    )
    write_set = snapshot.state.attempts.sole.write_set
    expect(write_set.to_h).to include(
      repository_id: "billing",
      policy_version: "coordinator-resource-key/v1"
    )
    expect(write_set.lease_set_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(write_set.resources).to eq(write_set.resources.sort_by { _1.resource_key_hash.b })
    expect(write_set.resources.map(&:resource_path)).to contain_exactly(
      "app/models/invoice.rb",
      "app/services/tax.rb",
      "db/schema.rb"
    )
    expect(write_set.resources.map(&:fencing_token)).to eq([ 1, 1, 1 ])
    expect(write_set.expires_at).to eq(renewal.expires_at)
    expect(write_set.last_expanded_at).to be > write_set.reserved_at
    expect(write_set.last_renewed_at).to be > write_set.reserved_at
    expect(write_set.previous_expires_at).to eq(reservation.expires_at)
    expect(write_set.released_at).to eq(release.released_at)
    expect(write_set.expires_at).to eq(release.previous_expires_at)
    expect(write_set.to_h.keys & %i[active fresh pending]).to be_empty
    expect(Coordinator::Read::ContextNextActionsBuilder.new.call(snapshot.state)).to be_empty
  end

  it "keeps the latest observed Candidate checkpoint per Attempt while history remains separate" do
    prepared = CandidateScenario.prepare(prefix: "context-candidate")
    first_input = prepared.fetch(:input)
    second_input = first_input.merge(
      command_id: "cmd-context-candidate-2",
      candidate_id: "CAN-context-candidate-2",
      head_commit_oid: "e" * 40,
      checkpoint_kind: "handoff"
    )
    CandidateScenario.execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, first_input)
    CandidateScenario.execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, second_input)
    project_candidate_context_sources(prepared.fetch(:ids))
    CandidateScenario.attachment_events(prepared.dig(:ids, :attempt_id)).each do |event|
      projector.call(event)
    end

    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "attempt",
      scope_id: prepared.dig(:ids, :attempt_id)
    )
    checkpoint = snapshot.state.candidate_checkpoints.sole
    expect(checkpoint).to have_attributes(
      candidate_id: "CAN-context-candidate-2",
      attempt_id: "A-context-candidate",
      checkpoint_kind: "handoff",
      head_commit_oid: "e" * 40,
      manifest_digest: match(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN)
    )
    expect(checkpoint.candidate_event).to have_attributes(
      stream_id: "CAN-context-candidate-2",
      type: "CandidateSubmitted"
    )
  end

  def create_change_set(change_set_id)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate #{change_set_id}",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def create_work_item(change_set_id, work_item_id)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id: "billing",
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
  end

  def project_candidate_context_sources(ids)
    planning = event_store.read(
      streams.change_set(ids.fetch(:change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
    work = event_store.read(
      streams.work_item(ids.fetch(:work_item_id)),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_ACQUISITION
    )
    attempt = event_store.read(
      streams.attempt(ids.fetch(:attempt_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AttemptAuthorized AttemptStarted WriteSetReserved],
        maximum_count: 3,
        direction: :asc
      )
    )
    event_types = %w[
      ChangeSetCreated
      ChangeSetAcceptanceCriteriaDefined
      WorkItemCreated
      WorkItemAddedToChangeSet
      ChangeSetActivated
      WorkItemMadeReady
      WorkItemAcquired
      AttemptAuthorized
      AttemptStarted
      WriteSetReserved
    ]
    events = planning + work + attempt
    event_types.each { |type| projector.call(events.find { _1.type == type }) }
  end
end
