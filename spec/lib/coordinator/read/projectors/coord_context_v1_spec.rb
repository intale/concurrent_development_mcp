# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CoordContextV1, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:projector) { described_class.new }

  it "keeps immutable pre-v3 write-set observations readable" do
    create_change_set("CS-HISTORICAL-V2")
    create_work_item("CS-HISTORICAL-V2", "W-HISTORICAL-V2")
    activate_change_set("CS-HISTORICAL-V2", "W-HISTORICAL-V2")
    acquire_work_item(
      "CS-HISTORICAL-V2",
      "W-HISTORICAL-V2",
      "A-HISTORICAL-V2",
      "agent-history"
    )
    event_store.append(
      streams.attempt("A-HISTORICAL-V2"),
      [ historical_v2_write_set_reserved ]
    )

    sources = change_set_events("CS-HISTORICAL-V2") +
              work_item_events("W-HISTORICAL-V2") +
              event_store.read(
                streams.attempt("A-HISTORICAL-V2"),
                Coordinator::Write::EventReadCriteria.new(
                  event_types: %w[AttemptAuthorized AttemptStarted WriteSetReserved],
                  maximum_count: 3,
                  direction: :asc
                )
              )
    sources.sort_by(&:global_position).each { projector.call(_1) }

    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "attempt",
      scope_id: "A-HISTORICAL-V2"
    )
    expect(snapshot.state.attempts.sole.write_set.policy_version)
      .to eq("coordinator-resource-key/v2")
  end

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
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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

  it "converges abandonment and requeue facts in either cross-stream order" do
    create_change_set("CS-ABANDON")
    create_work_item("CS-ABANDON", "W-ABANDON")
    activate_change_set("CS-ABANDON", "W-ABANDON")
    acquire_work_item("CS-ABANDON", "W-ABANDON", "A-ABANDON", "agent-a")
    abandon_attempt("CS-ABANDON", "W-ABANDON", "A-ABANDON", "agent-a")

    sources = abandonment_context_sources(
      change_set_id: "CS-ABANDON",
      work_item_id: "W-ABANDON",
      attempt_id: "A-ABANDON"
    )
    terminal = sources.select { %w[AttemptAbandoned WorkItemRequeued].include?(_1.type) }
    initial = sources - terminal

    initial.each { projector.call(_1) }
    terminal.each { projector.call(_1) }
    terminal.each { projector.call(_1) }
    first_document = Coordinator::Read::CoordContext.find("CS-ABANDON").document
    assert_abandoned_context

    ReadModelTestSafety.clean!
    initial.each { projector.call(_1) }
    terminal.reverse_each { projector.call(_1) }

    expect(Coordinator::Read::CoordContext.find("CS-ABANDON").document).to eq(first_document)
    assert_abandoned_context
  end

  it "keeps only the newest one hundred Attempts in embedded context" do
    reducer = Coordinator::Read::Projections::CoordContextReducer.new
    state = reducer.apply(
      Coordinator::Read::Projections::CoordContextStateV1.initial,
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id: "W-WINDOW",
        change_set_id: "CS-WINDOW",
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        goal: "Keep recent Attempts bounded",
        acceptance_criteria: [ "Older Attempts remain separately pageable" ],
        competitive_mode: false,
        created_at: "2026-08-27T10:00:00.000000Z"
      )
    )
    snapshot = Coordinator::Write::RepositorySnapshotV1.new(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      object_format: "sha1",
      commit_oid: "a" * 40
    )

    101.times do |offset|
      state = reducer.apply(
        state,
        Coordinator::Write::Events::AttemptAuthorizedV1.new(
          attempt_id: format("A-WINDOW-%03d", offset),
          change_set_id: "CS-WINDOW",
          work_item_id: "W-WINDOW",
          agent_id: "agent-window",
          base_snapshots: [ snapshot ],
          authorized_at: (Time.utc(2026, 8, 27, 10, 1) + offset).iso8601(6)
        )
      )
    end

    expect(state.attempts.length).to eq(100)
    expect(state.attempts.first.attempt_id).to eq("A-WINDOW-100")
    expect(state.attempts.last.attempt_id).to eq("A-WINDOW-001")
    expect(state.attempts.map(&:attempt_id)).not_to include("A-WINDOW-000")
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
        { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "a" * 40 }
      ]
    ).value!
    reservation = Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id: "reserve-A-100",
      actor: { kind: "agent", id: "agent-1" },
      change_set_id: "CS-100",
      work_item_id: "W-100",
      attempt_id: "A-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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
        {
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
          object_format: "sha1",
          commit_oid: "a" * 40
        }
      ]
    )
    write_set = snapshot.state.attempts.sole.write_set
    expect(write_set.to_h).to include(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      policy_version: "coordinator-resource-key/v3"
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

  it "serves observed final-Candidate context while terminal facts lag, then converges the ChangeSet" do
    candidate = CandidateScenario.submit(prefix: "context-terminal")
    ids = candidate.fetch(:ids)
    project_candidate_context_sources(ids)
    projector.call(candidate.fetch(:attachment))
    CandidateScenario.release(candidate)
    release = attempt_terminal_context_events(ids.fetch(:attempt_id)).find { _1.type == "WriteSetReleased" }
    projector.call(release)

    before_completion = Coordinator::Read::Queries::CoordContext.new.call(
      attempt_id: ids.fetch(:attempt_id)
    ).value!
    expect(before_completion.data.context.work_items.sole.status).to eq("acquired")
    expect(before_completion.next_actions.sole).to have_attributes(tool: "work_item_complete")
    expect(before_completion.next_actions.sole.arguments.to_h).to eq(
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      candidate_id: candidate.dig(:input, :candidate_id)
    )

    CandidateScenario.complete(candidate, release: false)
    stale = Coordinator::Read::Queries::CoordContext.new.call(attempt_id: ids.fetch(:attempt_id)).value!
    expect(stale.status).to eq("ok")
    expect(stale.context_token).to eq(before_completion.context_token)
    expect(stale.data.context.work_items.sole.status).to eq("acquired")

    terminal = work_item_terminal_context_events(ids.fetch(:work_item_id))
    attempt_completed = attempt_terminal_context_events(ids.fetch(:attempt_id)).find do |event|
      event.type == "AttemptCompleted"
    end
    projector.call(terminal.find { _1.type == "WorkItemCandidateSelected" })
    projector.call(attempt_completed)
    projector.call(terminal.find { _1.type == "WorkItemCompleted" })
    Coordinator::Processes::ProcessManagers::BuildProgress.new(event_store:).call(
      terminal.find { _1.type == "WorkItemCompleted" }
    )
    projector.call(change_set_terminal_context_events(ids.fetch(:change_set_id)).sole)

    converged = Coordinator::Read::Queries::CoordContext.new.call(
      change_set_id: ids.fetch(:change_set_id)
    ).value!
    expect(converged.status).to eq("ok")
    expect(converged.data.context.change_set).to have_attributes(
      status: "completed",
      completed_at: be_present
    )
    expect(converged.data.context.work_items.sole).to have_attributes(
      status: "completed",
      selected_candidate_id: candidate.dig(:input, :candidate_id),
      completed_at: be_present
    )
    expect(converged.data.context.work_items.sole.produced_outputs).to eq([])
    expect(converged.data.context.attempts.sole).to have_attributes(
      status: "completed",
      selected_candidate_id: candidate.dig(:input, :candidate_id),
      completed_at: be_present
    )
    expect(converged.next_actions).to be_empty
    expect(converged.to_h).not_to include(:projection_status, :fresh, :pending)
  end

  it "removes an observed dependency blocker before the independently projected readiness fact" do
    scenario = DependencyProgressScenario.prepare(
      prefix: "context-unlock",
      dependency_kind: "requires_completion"
    )
    ids = scenario.fetch(:ids)
    project_dependency_context_sources(ids)

    blocked = Coordinator::Read::Queries::CoordContext.new.call(
      work_item_id: ids.fetch(:consumer_work_item_id)
    ).value!
    expect(blocked.data.blockers.sole).to have_attributes(
      dependency_id: "DEP-progress-#{ids.fetch(:candidate_id)}"
    )

    completed = DependencyProgressScenario.complete(scenario)
    source = DependencyProgressScenario.work_item_event(completed, "WorkItemCompleted")
    Coordinator::Processes::ProcessManagers::BuildProgress.new(event_store:).call(source)
    satisfaction = DependencyProgressScenario.dependency_events(completed).sole
    readiness = DependencyProgressScenario.readiness_events(completed).sole
    projector.call(satisfaction)

    partially_converged = Coordinator::Read::Queries::CoordContext.new.call(
      work_item_id: ids.fetch(:consumer_work_item_id)
    ).value!
    expect(partially_converged.status).to eq("ok")
    expect(partially_converged.data.blockers).to be_empty
    expect(partially_converged.data.context.work_items.find do |work_item|
      work_item.work_item_id == ids.fetch(:consumer_work_item_id)
    end.status).to eq("planned")

    projector.call(readiness)
    converged = Coordinator::Read::Queries::CoordContext.new.call(
      work_item_id: ids.fetch(:consumer_work_item_id)
    ).value!
    expect(converged.data.blockers).to be_empty
    expect(converged.next_actions).to include(
      have_attributes(
        tool: "work_item_acquire",
        arguments: have_attributes(work_item_id: ids.fetch(:consumer_work_item_id))
      )
    )
    dependency = converged.data.context.dependencies.sole
    expect(dependency).to have_attributes(source_event: be_present, satisfied_at: be_present)
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

  def historical_v2_write_set_reserved
    PgEventstore::Event.new(
      id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type: "WriteSetReserved",
      data: {
        "lease_set_id" => "01919191-9191-7191-8191-919191919192",
        "change_set_id" => "CS-HISTORICAL-V2",
        "work_item_id" => "W-HISTORICAL-V2",
        "attempt_id" => "A-HISTORICAL-V2",
        "repository_id" => RepositoryScenario::DEFAULT_REPOSITORY_ID,
        "policy_version" => "coordinator-resource-key/v2",
        "resources" => [
          {
            "lease_id" => "01919191-9191-7191-8191-919191919191",
            "resource_key" => "scope:project:history:repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:file:old.rb",
            "resource_key_hash" => "sha256:#{'a' * 64}",
            "resource_kind" => "file",
            "resource_path" => "old.rb",
            "base_blob_oid" => nil,
            "fencing_token" => 1
          }
        ],
        "reserved_at" => "2026-08-22T10:00:00.000000Z",
        "expires_at" => "2026-08-22T10:15:00.000000Z"
      },
      metadata: { "schema_version" => 1 }
    )
  end

  def create_work_item(change_set_id, work_item_id)
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def activate_change_set(change_set_id, work_item_id)
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "activate-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    ).value!
    activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    raise "WorkItem #{work_item_id} was not made ready" unless work_item_events(work_item_id).any? do |event|
      event.type == "WorkItemMadeReady"
    end
  end

  def acquire_work_item(change_set_id, work_item_id, attempt_id, agent_id)
    Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
      command_id: "acquire-#{attempt_id}",
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id:,
      attempt_id:,
      base_snapshots: [
        { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "a" * 40 }
      ]
    ).value!
  end

  def abandon_attempt(change_set_id, work_item_id, attempt_id, agent_id)
    Coordinator::Write::Operations::ExecuteAbandonAttempt.new(event_store:).call(
      command_id: "abandon-#{attempt_id}",
      actor: { kind: "agent", id: agent_id },
      change_set_id:,
      work_item_id:,
      attempt_id:,
      reason: "The agent yielded this WorkItem."
    ).value!
  end

  def abandonment_context_sources(change_set_id:, work_item_id:, attempt_id:)
    change_set = change_set_events(change_set_id)
    work_item = event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WorkItemCreated WorkItemMadeReady WorkItemAcquired WorkItemRequeued],
        maximum_count: 4,
        direction: :asc
      )
    )
    attempt = event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AttemptAuthorized AttemptStarted AttemptAbandoned],
        maximum_count: 3,
        direction: :asc
      )
    )

    (change_set + work_item + attempt).sort_by(&:global_position)
  end

  def assert_abandoned_context
    snapshot = Coordinator::Read::Repositories::CoordContexts.new.resolve(
      scope_kind: "work_item",
      scope_id: "W-ABANDON"
    )
    expect(snapshot.state.work_items.sole).to have_attributes(
      status: "ready",
      active_attempt_id: nil,
      active_agent_id: nil
    )
    expect(snapshot.state.attempts.sole).to have_attributes(
      attempt_id: "A-ABANDON",
      agent_id: "agent-a",
      status: "abandoned",
      abandonment_reason: "The agent yielded this WorkItem.",
      abandoned_at: be_present
    )
    history = Coordinator::Read::Repositories::CoordContexts.new.attempt_page(
      work_item_id: "W-ABANDON",
      after_authorized_global_position: nil,
      limit: 1
    ).items.sole
    expect(history).to have_attributes(
      attempt_id: "A-ABANDON",
      work_item_id: "W-ABANDON",
      agent_id: "agent-a",
      status: "abandoned",
      abandonment_reason: "The agent yielded this WorkItem.",
      terminal_at: be_present
    )
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

  def project_dependency_context_sources(ids)
    planning = event_store.read(
      streams.change_set(ids.fetch(:change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
    producer = work_item_context_events(ids.fetch(:producer_work_item_id))
    consumer = work_item_context_events(ids.fetch(:consumer_work_item_id))
    attempt = event_store.read(
      streams.attempt(ids.fetch(:attempt_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AttemptAuthorized AttemptStarted WriteSetReserved CandidateAttachedToAttempt],
        maximum_count: 4,
        direction: :asc
      )
    )
    (planning + producer + consumer + attempt).sort_by(&:global_position).each { projector.call(_1) }
  end

  def work_item_context_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WorkItemCreated WorkItemMadeReady WorkItemAcquired],
        maximum_count: 3,
        direction: :asc
      )
    )
  end

  def work_item_terminal_context_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WorkItemCandidateSelected WorkItemCompleted],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def attempt_terminal_context_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WriteSetReleased AttemptCompleted],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def change_set_terminal_context_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ChangeSetCompleted" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end
end
