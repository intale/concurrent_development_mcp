# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CoordContextV1, :read_model do
  subject(:projector) { described_class.new(submission_loader:) }

  let(:repository) { Coordinator::Read::Repositories::CoordContexts.new }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000601" }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:candidate_submissions) { {} }
  let(:submission_loader) do
    Class.new do
      def initialize(submissions)
        @submissions = submissions
      end

      def call(candidate_id)
        @submissions.fetch(candidate_id)
      end
    end.new(candidate_submissions)
  end

  it "atomically projects exact source identities and ignores duplicate delivery" do
    events = planning_events(change_set_id: "CS-100", work_item_id: "W-100")
    %i[created criteria membership work_item].each { projector.call(events.fetch(_1)) }
    projector.call(events.fetch(:work_item))

    snapshot = repository.resolve(scope_kind: "work_item", scope_id: "W-100")
    expect(snapshot.state.change_set.to_h).to include(
      change_set_id: "CS-100",
      goal: "Coordinate CS-100",
      acceptance_criteria: [ "Agents do not overlap" ]
    )
    expect(snapshot.state.work_item_ids).to eq([ "W-100" ])
    expect(snapshot.state.work_items.sole.to_h).to include(
      work_item_id: "W-100",
      repository_id:,
      status: "planned"
    )
    expect(snapshot.source_positions.length).to eq(2)
    expect(Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "coord_context").count).to eq(4)
  end

  it "converges when cross-stream WorkItem siblings arrive in either order" do
    events = planning_events(change_set_id: "CS-ORDER", work_item_id: "W-ORDER")
    [ events.fetch(:created), events.fetch(:criteria), events.fetch(:membership), events.fetch(:work_item) ]
      .each { projector.call(_1) }
    first_document = Coordinator::Read::CoordContext.find("CS-ORDER").document

    ReadModelTestSafety.clean!
    [ events.fetch(:created), events.fetch(:criteria), events.fetch(:work_item), events.fetch(:membership) ]
      .each { projector.call(_1) }

    expect(Coordinator::Read::CoordContext.find("CS-ORDER").document).to eq(first_document)
  end

  it "converges abandonment and requeue facts in either cross-stream order" do
    events = active_attempt_events(
      change_set_id: "CS-ABANDON",
      work_item_id: "W-ABANDON",
      attempt_id: "A-ABANDON",
      agent_id: "agent-a"
    )
    abandoned = attempt_event(
      Coordinator::Write::Events::AttemptAbandonedV2.new(
        change_set_id: "CS-ABANDON",
        work_item_id: "W-ABANDON",
        attempt_id: "A-ABANDON",
        agent_id: "agent-a",
        reason: "The agent yielded this WorkItem.",
        lease_set_id: nil,
        released_leases: [],
        untouched_resource_ids: [],
        abandoned_at: "2026-08-30T12:05:00.000000Z"
      ),
      attempt_id: "A-ABANDON",
      revision: 2,
      position: 500
    )
    requeued = work_item_event(
      Coordinator::Write::Events::WorkItemRequeuedV1.new(
        change_set_id: "CS-ABANDON",
        work_item_id: "W-ABANDON",
        attempt_id: "A-ABANDON",
        agent_id: "agent-a",
        reason: "The agent yielded this WorkItem.",
        requeued_at: "2026-08-30T12:05:01.000000Z"
      ),
      work_item_id: "W-ABANDON",
      revision: 3,
      position: 501
    )

    events.each { projector.call(_1) }
    [ abandoned, requeued, abandoned, requeued ].each { projector.call(_1) }
    first_document = Coordinator::Read::CoordContext.find("CS-ABANDON").document
    assert_abandoned_context

    ReadModelTestSafety.clean!
    events.each { projector.call(_1) }
    [ requeued, abandoned ].each { projector.call(_1) }

    expect(Coordinator::Read::CoordContext.find("CS-ABANDON").document).to eq(first_document)
    assert_abandoned_context
  end

  it "retains every nonterminal Attempt and fills the remaining bound with recent terminal Attempts" do
    reducer = Coordinator::Read::Projections::CoordContextReducer.new
    state = reducer.apply(
      Coordinator::Read::Projections::CoordContextStateV1.initial,
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id: "W-WINDOW-ACTIVE",
        change_set_id: "CS-WINDOW",
        repository_id:,
        goal: "Keep an old active Attempt addressable",
        acceptance_criteria: [ "Lease lifecycle events continue to reduce" ],
        competitive_mode: false,
        created_at: "2026-08-30T10:00:00.000000Z"
      )
    )
    state = reducer.apply(
      state,
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id: "W-WINDOW-HISTORY",
        change_set_id: "CS-WINDOW",
        repository_id:,
        goal: "Accumulate terminal Attempt history",
        acceptance_criteria: [ "Recent terminal Attempts remain embedded" ],
        competitive_mode: false,
        created_at: "2026-08-30T10:00:01.000000Z"
      )
    )
    snapshot = Coordinator::Write::RepositorySnapshotV1.new(
      repository_id:,
      object_format: "sha1",
      commit_oid: "a" * 40
    )
    state = reducer.apply(
      state,
      Coordinator::Write::Events::AttemptAuthorizedV1.new(
        attempt_id: "A-WINDOW-ACTIVE",
        change_set_id: "CS-WINDOW",
        work_item_id: "W-WINDOW-ACTIVE",
        agent_id: "agent-active",
        base_snapshots: [ snapshot ],
        authorized_at: "2026-08-30T10:01:00.000000Z"
      )
    )

    100.times do |offset|
      attempt_id = format("A-WINDOW-TERMINAL-%03d", offset)
      authorized_at = (Time.utc(2026, 8, 30, 10, 2) + offset).iso8601(6)
      state = reducer.apply(
        state,
        Coordinator::Write::Events::AttemptAuthorizedV1.new(
          attempt_id:,
          change_set_id: "CS-WINDOW",
          work_item_id: "W-WINDOW-HISTORY",
          agent_id: "agent-window",
          base_snapshots: [ snapshot ],
          authorized_at:
        )
      )
      state = reducer.apply(
        state,
        Coordinator::Write::Events::AttemptAbandonedV2.new(
          change_set_id: "CS-WINDOW",
          work_item_id: "W-WINDOW-HISTORY",
          attempt_id:,
          agent_id: "agent-window",
          reason: "Exercise the bounded terminal window",
          lease_set_id: nil,
          released_leases: [],
          untouched_resource_ids: [],
          abandoned_at: (Time.iso8601(authorized_at) + 0.5).iso8601(6)
        )
      )
    end

    expect(state.attempts.length).to eq(100)
    expect(state.attempts.map(&:attempt_id)).to include("A-WINDOW-ACTIVE")
    expect(state.attempts.map(&:attempt_id)).not_to include("A-WINDOW-TERMINAL-000")
    expect(state.attempts.count { %w[abandoned completed].include?(_1.status) }).to eq(99)
  end

  it "projects activation, ownership, exact Attempt bases, and observed write-set evidence" do
    events = active_attempt_events(
      change_set_id: "CS-WRITE",
      work_item_id: "W-WRITE",
      attempt_id: "A-WRITE",
      agent_id: "agent-1"
    )
    reserved_resources = [
      lease_reference(resource_suffix: "611", lease_suffix: "621", path: "app/models/invoice.rb", blob: "b" * 40),
      lease_reference(resource_suffix: "613", lease_suffix: "623", path: "db/schema.rb", blob: nil)
    ]
    added_resource = lease_reference(
      resource_suffix: "612",
      lease_suffix: "622",
      path: "app/services/tax.rb",
      blob: "c" * 40
    )
    lease_set_id = "018f0f4d-4e45-7abc-8def-000000000620"
    reserved = write_set_event(
      Coordinator::Write::Events::WriteSetReservedV2.new(
        lease_set_id:,
        change_set_id: "CS-WRITE",
        work_item_id: "W-WRITE",
        attempt_id: "A-WRITE",
        repository_id:,
        policy_version: "coordinator-resource-lease/v2",
        resources: reserved_resources,
        reserved_at: "2026-08-30T12:02:00.000000Z",
        expires_at: "2026-08-30T12:10:00.000000Z"
      ),
      attempt_id: "A-WRITE",
      revision: 2,
      position: 500
    )
    expanded = write_set_event(
      Coordinator::Write::Events::WriteSetExpandedV2.new(
        lease_set_id:,
        change_set_id: "CS-WRITE",
        work_item_id: "W-WRITE",
        attempt_id: "A-WRITE",
        repository_id:,
        policy_version: "coordinator-resource-lease/v2",
        added_resources: [ added_resource ],
        resource_count: 3,
        expanded_at: "2026-08-30T12:03:00.000000Z",
        expires_at: "2026-08-30T12:10:00.000000Z"
      ),
      attempt_id: "A-WRITE",
      revision: 3,
      position: 600
    )
    all_resources = [ *reserved_resources, added_resource ].sort_by { _1.resource_id.b }
    renewed = write_set_event(
      Coordinator::Write::Events::WriteSetRenewedV2.new(
        lease_set_id:,
        change_set_id: "CS-WRITE",
        work_item_id: "W-WRITE",
        attempt_id: "A-WRITE",
        repository_id:,
        policy_version: "coordinator-resource-lease/v2",
        resources: all_resources,
        resource_count: 3,
        renewed_at: "2026-08-30T12:04:00.000000Z",
        previous_expires_at: "2026-08-30T12:10:00.000000Z",
        expires_at: "2026-08-30T12:20:00.000000Z"
      ),
      attempt_id: "A-WRITE",
      revision: 4,
      position: 700
    )
    released = write_set_event(
      Coordinator::Write::Events::WriteSetReleasedV2.new(
        lease_set_id:,
        change_set_id: "CS-WRITE",
        work_item_id: "W-WRITE",
        attempt_id: "A-WRITE",
        repository_id:,
        policy_version: "coordinator-resource-lease/v2",
        resources: all_resources,
        resource_count: 3,
        previous_expires_at: "2026-08-30T12:20:00.000000Z",
        released_at: "2026-08-30T12:05:00.000000Z"
      ),
      attempt_id: "A-WRITE",
      revision: 5,
      position: 800
    )
    [ *events, reserved, expanded, expanded, renewed, renewed, released, released ].each { projector.call(_1) }

    snapshot = repository.resolve(scope_kind: "attempt", scope_id: "A-WRITE")
    expect(snapshot.state.change_set.status).to eq("active")
    expect(snapshot.state.work_items.sole.to_h).to include(
      status: "acquired",
      active_attempt_id: "A-WRITE",
      active_agent_id: "agent-1"
    )
    expect(snapshot.state.attempts.sole.to_h).to include(
      attempt_id: "A-WRITE",
      status: "started",
      base_snapshots: [ { repository_id:, object_format: "sha1", commit_oid: "a" * 40 } ]
    )
    write_set = snapshot.state.attempts.sole.write_set
    expect(write_set.to_h).to include(repository_id:, policy_version: "coordinator-resource-lease/v2")
    expect(write_set.lease_set_id).to eq(lease_set_id)
    expect(write_set.resources).to eq(write_set.resources.sort_by { _1.resource_id.b })
    expect(write_set.resources.map(&:resource_path)).to contain_exactly(
      "app/models/invoice.rb", "app/services/tax.rb", "db/schema.rb"
    )
    expect(write_set.resources.map(&:fencing_token)).to eq([ 1, 1, 1 ])
    expect(write_set).to have_attributes(
      reserved_at: "2026-08-30T12:02:00.000000Z",
      last_expanded_at: "2026-08-30T12:03:00.000000Z",
      last_renewed_at: "2026-08-30T12:04:00.000000Z",
      previous_expires_at: "2026-08-30T12:10:00.000000Z",
      expires_at: "2026-08-30T12:20:00.000000Z",
      released_at: "2026-08-30T12:05:00.000000Z"
    )
    expect(write_set.to_h.keys & %i[active fresh pending]).to be_empty

    history = Coordinator::Read::AttemptHistory.find("A-WRITE")
    expect(history).to have_attributes(
      write_set_lease_set_id: lease_set_id,
      write_set_repository_id: repository_id,
      write_set_policy_version: "coordinator-resource-lease/v2",
      write_set_reserved_at_domain: Time.iso8601("2026-08-30T12:02:00.000000Z"),
      write_set_last_expanded_at_domain: Time.iso8601("2026-08-30T12:03:00.000000Z"),
      write_set_last_renewed_at_domain: Time.iso8601("2026-08-30T12:04:00.000000Z"),
      write_set_previous_expires_at_domain: Time.iso8601("2026-08-30T12:10:00.000000Z"),
      write_set_expires_at_domain: Time.iso8601("2026-08-30T12:20:00.000000Z"),
      write_set_released_at_domain: Time.iso8601("2026-08-30T12:05:00.000000Z")
    )
    expect(history.write_set_resources.map { _1.fetch("resource_path") }).to contain_exactly(
      "app/models/invoice.rb", "app/services/tax.rb", "db/schema.rb"
    )
    expect(history.write_set_reserved_event.fetch("event_id")).to eq(reserved.id)
    expect(history.write_set_last_expanded_event.fetch("event_id")).to eq(expanded.id)
    expect(history.write_set_last_renewed_event.fetch("event_id")).to eq(renewed.id)
    expect(history.write_set_release_event.fetch("event_id")).to eq(released.id)
  end

  it "keeps the latest observed Candidate checkpoint per Attempt while history remains separate" do
    events = active_attempt_events(
      change_set_id: "CS-CANDIDATE",
      work_item_id: "W-CANDIDATE",
      attempt_id: "A-CANDIDATE",
      agent_id: "agent-a"
    )
    first = candidate_submitted_event(
      change_set_id: "CS-CANDIDATE",
      work_item_id: "W-CANDIDATE",
      attempt_id: "A-CANDIDATE",
      candidate_id: "CAN-context-candidate-1",
      checkpoint_kind: "intermediate",
      head_character: "b",
      revision: 2,
      position: 500
    )
    second = candidate_submitted_event(
      change_set_id: "CS-CANDIDATE",
      work_item_id: "W-CANDIDATE",
      attempt_id: "A-CANDIDATE",
      candidate_id: "CAN-context-candidate-2",
      checkpoint_kind: "handoff",
      head_character: "e",
      revision: 3,
      position: 600
    )
    [ *events, first, second ].each { projector.call(_1) }

    checkpoint = repository.resolve(scope_kind: "attempt", scope_id: "A-CANDIDATE")
      .state.candidate_checkpoints.sole
    expect(checkpoint).to have_attributes(
      candidate_id: "CAN-context-candidate-2",
      attempt_id: "A-CANDIDATE",
      checkpoint_kind: "handoff",
      head_commit_oid: "e" * 40,
      manifest_digest: digest("e")
    )
    expect(checkpoint.candidate_event).to have_attributes(
      stream_id: "CAN-context-candidate-2",
      type: "CandidateSubmitted"
    )
  end

  it "serves observed final-Candidate context while terminal facts lag, then converges the ChangeSet" do
    change_set_id = "CS-TERMINAL"
    work_item_id = "W-TERMINAL"
    attempt_id = "A-TERMINAL"
    candidate_id = "CAN-context-terminal"
    events = active_attempt_events(change_set_id:, work_item_id:, attempt_id:, agent_id: "agent-a")
    lease = lease_reference(resource_suffix: "631", lease_suffix: "632", path: "app/final.rb", blob: "b" * 40)
    lease_set_id = "018f0f4d-4e45-7abc-8def-000000000630"
    reserved = write_set_event(
      Coordinator::Write::Events::WriteSetReservedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: "coordinator-resource-lease/v2",
        resources: [ lease ],
        reserved_at: "2026-08-30T12:02:00.000000Z",
        expires_at: "2026-08-30T12:10:00.000000Z"
      ),
      attempt_id:,
      revision: 2,
      position: 500
    )
    submitted = candidate_submitted_event(
      change_set_id:,
      work_item_id:,
      attempt_id:,
      candidate_id:,
      checkpoint_kind: "final",
      head_character: "e",
      revision: 3,
      position: 600
    )
    released = write_set_event(
      Coordinator::Write::Events::WriteSetReleasedV2.new(
        lease_set_id:,
        change_set_id:,
        work_item_id:,
        attempt_id:,
        repository_id:,
        policy_version: "coordinator-resource-lease/v2",
        resources: [ lease ],
        resource_count: 1,
        previous_expires_at: "2026-08-30T12:10:00.000000Z",
        released_at: "2026-08-30T12:03:00.000000Z"
      ),
      attempt_id:,
      revision: 4,
      position: 700
    )
    [ *events, reserved, submitted, released ].each { projector.call(_1) }

    before_completion = Coordinator::Read::Queries::CoordContext.new.call(attempt_id:).value!
    expect(before_completion.data.context.work_items.sole.status).to eq("acquired")

    candidate_reference = event_reference(submitted)
    selected = work_item_event(
      Coordinator::Write::Events::WorkItemCandidateSelectedV1.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        candidate_id:,
        candidate_event: candidate_reference,
        selected_at: "2026-08-30T12:04:00.000000Z"
      ),
      work_item_id:,
      revision: 3,
      position: 800
    )
    attempt_completed = attempt_event(
      Coordinator::Write::Events::AttemptCompletedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        candidate_id:,
        candidate_event: candidate_reference,
        completed_at: "2026-08-30T12:04:01.000000Z"
      ),
      attempt_id:,
      revision: 5,
      position: 801
    )
    work_completed = work_item_event(
      Coordinator::Write::Events::WorkItemCompletedV1.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        candidate_id:,
        candidate_event: candidate_reference,
        produced_outputs: [],
        rule_version: "work-item-completion/v1",
        completed_at: "2026-08-30T12:04:02.000000Z"
      ),
      work_item_id:,
      revision: 4,
      position: 802
    )
    change_completed = change_set_event(
      Coordinator::Write::Events::ChangeSetCompletedV1.new(
        change_set_id:,
        work_item_completions: [
          Coordinator::Write::ChangeSetCompletions::WorkItemEvidenceV1.new(
            change_set_id:,
            work_item_id:,
            repository_id:,
            attempt_id:,
            candidate_id:,
            candidate_event: candidate_reference,
            selected_event: event_reference(selected),
            completed_event: event_reference(work_completed),
            completed_at: "2026-08-30T12:04:02.000000Z"
          )
        ],
        release_set_completion_event: nil,
        rule_version: "change-set-completion/v1",
        completed_at: "2026-08-30T12:05:00.000000Z"
      ),
      change_set_id:,
      revision: 4,
      position: 900
    )
    [ selected, attempt_completed, work_completed, change_completed ].each { projector.call(_1) }

    converged = Coordinator::Read::Queries::CoordContext.new.call(change_set_id:).value!
    expect(converged.status).to eq("ok")
    expect(converged.data.context.change_set).to have_attributes(status: "completed", completed_at: be_present)
    expect(converged.data.context.work_items.sole).to have_attributes(
      status: "completed",
      selected_candidate_id: candidate_id,
      completed_at: be_present,
      produced_outputs: []
    )
    expect(converged.data.context.attempts.sole).to have_attributes(
      status: "completed",
      write_set: nil,
      selected_candidate_id: candidate_id,
      completed_at: be_present
    )
    expect(converged.to_h).not_to include(:projection_status, :fresh, :pending)
  end

  it "removes an observed dependency blocker before the independently projected readiness fact" do
    change_set_id = "CS-DEPENDENCY"
    producer_id = "W-PRODUCER"
    consumer_id = "W-CONSUMER"
    dependency_id = "DEP-context-unlock"
    events = dependency_planning_events(
      change_set_id:,
      producer_id:,
      consumer_id:,
      dependency_id:
    )
    events.each { projector.call(_1) }

    blocked = Coordinator::Read::Queries::CoordContext.new.call(work_item_id: consumer_id).value!
    expect(blocked.data.blockers.sole).to have_attributes(dependency_id:)

    source = source_reference("WorkItemCompleted", "WorkItem", producer_id, 4)
    satisfied = change_set_event(
      Coordinator::Write::Events::WorkItemDependencySatisfiedV1.new(
        change_set_id:,
        dependency_id:,
        producer_work_item_id: producer_id,
        consumer_work_item_id: consumer_id,
        dependency_kind: "requires_completion",
        required_output: nil,
        source_event: source,
        rule_version: "dependency-satisfaction/v1",
        satisfied_at: "2026-08-30T12:06:00.000000Z"
      ),
      change_set_id:,
      revision: 6,
      position: 700
    )
    projector.call(satisfied)

    partially_converged = Coordinator::Read::Queries::CoordContext.new.call(work_item_id: consumer_id).value!
    expect(partially_converged.status).to eq("ok")
    expect(partially_converged.data.blockers).to be_empty
    expect(partially_converged.data.context.work_items.find { _1.work_item_id == consumer_id }.status).to eq("planned")

    ready = work_item_event(
      Coordinator::Write::Events::WorkItemMadeReadyV1.new(
        change_set_id:,
        work_item_id: consumer_id,
        readiness_decision_id: "ready-consumer",
        reason: "dependencies_satisfied",
        made_ready_at: "2026-08-30T12:06:01.000000Z"
      ),
      work_item_id: consumer_id,
      revision: 1,
      position: 701
    )
    projector.call(ready)
    converged = Coordinator::Read::Queries::CoordContext.new.call(work_item_id: consumer_id).value!
    expect(converged.data.blockers).to be_empty
    expect(converged.next_actions).to be_empty
    expect(converged.data.context.dependencies.sole).to have_attributes(
      source_event: source,
      satisfied_at: "2026-08-30T12:06:00.000000Z"
    )
  end

  def planning_events(change_set_id:, work_item_id:)
    {
      created: change_set_event(
        Coordinator::Write::Events::ChangeSetCreatedV1.new(
          change_set_id:,
          goal: "Coordinate #{change_set_id}",
          created_at: "2026-08-30T12:00:00.000000Z"
        ),
        change_set_id:,
        revision: 0,
        position: 100
      ),
      criteria: change_set_event(
        Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV1.new(
          change_set_id:,
          acceptance_criteria: [ "Agents do not overlap" ],
          defined_at: "2026-08-30T12:00:01.000000Z"
        ),
        change_set_id:,
        revision: 1,
        position: 101
      ),
      membership: change_set_event(
        Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
          change_set_id:,
          work_item_id:,
          added_at: "2026-08-30T12:00:02.000000Z"
        ),
        change_set_id:,
        revision: 2,
        position: 102
      ),
      work_item: work_item_event(
        work_item_payload(change_set_id:, work_item_id:),
        work_item_id:,
        revision: 0,
        position: 200
      )
    }
  end

  def active_attempt_events(change_set_id:, work_item_id:, attempt_id:, agent_id:)
    planning = planning_events(change_set_id:, work_item_id:)
    activated = change_set_event(
      Coordinator::Write::Events::ChangeSetActivatedV1.new(
        change_set_id:,
        work_item_count: 1,
        dependency_count: 0,
        activated_at: "2026-08-30T12:00:03.000000Z"
      ),
      change_set_id:,
      revision: 3,
      position: 103
    )
    ready = work_item_event(
      Coordinator::Write::Events::WorkItemMadeReadyV1.new(
        change_set_id:,
        work_item_id:,
        readiness_decision_id: "ready-#{work_item_id}",
        reason: "change_set_activated",
        made_ready_at: "2026-08-30T12:00:04.000000Z"
      ),
      work_item_id:,
      revision: 1,
      position: 201
    )
    acquired = work_item_event(
      Coordinator::Write::Events::WorkItemAcquiredV1.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        agent_id:,
        acquired_at: "2026-08-30T12:01:00.000000Z"
      ),
      work_item_id:,
      revision: 2,
      position: 202
    )
    authorized = attempt_event(
      Coordinator::Write::Events::AttemptAuthorizedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        agent_id:,
        base_snapshots: [ repository_snapshot ],
        authorized_at: "2026-08-30T12:01:00.000000Z"
      ),
      attempt_id:,
      revision: 0,
      position: 300
    )
    started = attempt_event(
      Coordinator::Write::Events::AttemptStartedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        started_at: "2026-08-30T12:01:01.000000Z"
      ),
      attempt_id:,
      revision: 1,
      position: 301
    )
    [
      planning.fetch(:created), planning.fetch(:criteria), planning.fetch(:membership),
      planning.fetch(:work_item), activated, ready, acquired, authorized, started
    ]
  end

  def dependency_planning_events(change_set_id:, producer_id:, consumer_id:, dependency_id:)
    created = change_set_event(
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id:,
        goal: "Coordinate dependency",
        created_at: "2026-08-30T12:00:00.000000Z"
      ),
      change_set_id:,
      revision: 0,
      position: 100
    )
    criteria = change_set_event(
      Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV1.new(
        change_set_id:,
        acceptance_criteria: [ "Dependencies converge" ],
        defined_at: "2026-08-30T12:00:01.000000Z"
      ),
      change_set_id:,
      revision: 1,
      position: 101
    )
    memberships = [ producer_id, consumer_id ].each_with_index.map do |work_item_id, index|
      change_set_event(
        Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
          change_set_id:,
          work_item_id:,
          added_at: "2026-08-30T12:00:0#{index + 2}.000000Z"
        ),
        change_set_id:,
        revision: index + 2,
        position: 102 + index
      )
    end
    declared = change_set_event(
      Coordinator::Write::Events::WorkItemDependencyDeclaredV1.new(
        change_set_id:,
        dependency_id:,
        producer_work_item_id: producer_id,
        consumer_work_item_id: consumer_id,
        dependency_kind: "requires_completion",
        required_output: nil,
        declared_at: "2026-08-30T12:00:04.000000Z"
      ),
      change_set_id:,
      revision: 4,
      position: 104
    )
    activated = change_set_event(
      Coordinator::Write::Events::ChangeSetActivatedV1.new(
        change_set_id:,
        work_item_count: 2,
        dependency_count: 1,
        activated_at: "2026-08-30T12:00:05.000000Z"
      ),
      change_set_id:,
      revision: 5,
      position: 105
    )
    work_items = [ producer_id, consumer_id ].each_with_index.map do |work_item_id, index|
      work_item_event(
        work_item_payload(change_set_id:, work_item_id:),
        work_item_id:,
        revision: 0,
        position: 200 + index
      )
    end
    [ created, criteria, *memberships, *work_items, declared, activated ]
  end

  def work_item_payload(change_set_id:, work_item_id:)
    Coordinator::Write::Events::WorkItemCreatedV1.new(
      work_item_id:,
      change_set_id:,
      repository_id:,
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ],
      competitive_mode: false,
      created_at: "2026-08-30T12:00:02.000000Z"
    )
  end

  def candidate_submitted_event(
    change_set_id:,
    work_item_id:,
    attempt_id:,
    candidate_id:,
    checkpoint_kind:,
    head_character:,
    revision:,
    position:
  )
    submitted = projection_event(
      payload: Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:),
      stream: Coordinator::Write::StreamFactory.new.candidate(candidate_id),
      revision:,
      position:
    )
    manifest = Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id:,
      evidence_revision: 1,
      files: [
        Coordinator::Write::Candidates::ManifestFileV1.new(
          status: "modified",
          old_path: "lib/context.rb",
          new_path: "lib/context.rb",
          old_blob_oid: "a" * 40,
          new_blob_oid: head_character * 40,
          old_mode: "100644",
          new_mode: "100644"
        )
      ]
    )
    manifest_event = projection_event(
      payload: manifest,
      stream: Coordinator::Write::StreamFactory.new.candidate(candidate_id),
      revision: revision - 1,
      position: position - 1
    )
    candidate_submissions[candidate_id] = Coordinator::Read::CandidateSubmissionViewV2.new(
      candidate_id:,
      change_set_id:,
      work_item_id:,
      attempt_id:,
      agent_id: "agent-a",
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: head_character * 40,
      checkpoint_kind:,
      intention_set_id: SecureRandom.uuid_v7,
      lease_references: [
        Coordinator::Write::LeaseReferenceV2.new(
          lease_id: SecureRandom.uuid_v7,
          resource_id: SecureRandom.uuid_v7,
          resource_kind: "file",
          resource_path: "lib/context.rb",
          base_blob_oid: "a" * 40,
          fencing_token: 1
        )
      ],
      manifest_digest: digest(head_character),
      build_context_digest: nil,
      evidence_status: "attributed_unverified",
      manifest:,
      build_context: nil,
      submitted_event: submitted,
      manifest_event:,
      build_context_event: nil
    )
    submitted
  end

  def lease_reference(resource_suffix:, lease_suffix:, path:, blob:)
    Coordinator::Write::LeaseReferenceV2.new(
      lease_id: "018f0f4d-4e45-7abc-8def-000000000#{lease_suffix}",
      resource_id: "018f0f4d-4e45-7abc-8def-000000000#{resource_suffix}",
      resource_kind: "file",
      resource_path: path,
      base_blob_oid: blob,
      fencing_token: 1
    )
  end

  def repository_snapshot
    Coordinator::Write::RepositorySnapshotV1.new(
      repository_id:,
      object_format: "sha1",
      commit_oid: "a" * 40
    )
  end

  def change_set_event(payload, change_set_id:, revision:, position:)
    projection_event(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.change_set(change_set_id),
      revision:,
      position:
    )
  end

  def work_item_event(payload, work_item_id:, revision:, position:)
    projection_event(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.work_item(work_item_id),
      revision:,
      position:
    )
  end

  def attempt_event(payload, attempt_id:, revision:, position:)
    projection_event(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.attempt(attempt_id),
      revision:,
      position:
    )
  end

  alias_method :write_set_event, :attempt_event

  def projection_event(payload:, stream:, revision:, position:)
    ProjectionEventFactory.build(
      payload:,
      stream:,
      stream_revision: revision,
      global_position: position,
      policy_version: "coord-context/v1",
      command_id: "cmd-coord-context-projection",
      correlation_id:
    )
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: stream_name == "Decision" ? "HumanGuidance" : "DevelopmentExecution",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def event_payload(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def assert_abandoned_context
    snapshot = repository.resolve(scope_kind: "work_item", scope_id: "W-ABANDON")
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
    history = repository.attempt_page(
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

  def digest(character)
    "sha256:#{character * 64}"
  end
end
