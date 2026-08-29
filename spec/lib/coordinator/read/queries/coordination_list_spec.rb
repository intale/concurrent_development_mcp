# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::CoordinationList, :event_store, :read_model do
  subject(:query) { described_class.new }

  REPOSITORY_IDS = %w[
    018f0f4d-4e45-7abc-8def-000000000011
    018f0f4d-4e45-7abc-8def-000000000012
    018f0f4d-4e45-7abc-8def-000000000013
  ].freeze

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_projector) { Coordinator::Read::Projectors::RepositoriesV1.new }
  let(:context_projector) { Coordinator::Read::Projectors::CoordContextV1.new }

  it "discovers bounded resumable coordination from exact projected Repository scope" do
    first = create_coordination(
      prefix: "DISC-A",
      scope: "project:discovery",
      repository_id: REPOSITORY_IDS.fetch(0),
      label: "shared-build",
      checkpoint: true
    )
    second = create_coordination(
      prefix: "DISC-B",
      scope: "project:discovery",
      repository_id: REPOSITORY_IDS.fetch(1),
      label: "shared-build"
    )
    create_coordination(
      prefix: "OTHER",
      scope: "project:other",
      repository_id: REPOSITORY_IDS.fetch(2),
      label: "shared-build"
    )

    first_page = query.call(scope: "project:discovery", statuses: [ "active" ], limit: 1).value!
    expect(first_page).to have_attributes(status: "ok")
    expect(first_page.warnings).to contain_exactly(match(/projection-derived/))
    expect(first_page.to_h.keys & %i[fresh pending projection_status stream_revision]).to be_empty
    expect(first_page.data.page).to have_attributes(has_more: true)
    expect(first_page.next_actions.map(&:tool)).to contain_exactly("coord_context", "coordination_list")

    cursor = first_page.data.page.continuation_cursor
    second_page = query.call(
      scope: "project:discovery",
      statuses: [ "active" ],
      cursor: cursor.to_h,
      limit: 1
    ).value!
    discovered = [ *first_page.data.page.items, *second_page.data.page.items ]
    expect(discovered.map(&:change_set_id)).to contain_exactly(
      first.dig(:ids, :change_set_id),
      second.dig(:ids, :change_set_id)
    )
    expect(discovered.map(&:goal)).to all(include("shared-build"))
    checkpointed = discovered.find { _1.change_set_id == first.dig(:ids, :change_set_id) }
    expect(checkpointed).to have_attributes(
      repository_ids: [ REPOSITORY_IDS.fetch(0) ],
      work_item_ids: [ first.dig(:ids, :work_item_id) ],
      active_attempt_ids: [ first.dig(:ids, :attempt_id) ],
      candidate_checkpoint_count: 1
    )
  end

  it "keeps an older scoped view available until a valid Candidate checkpoint is projected" do
    coordination = create_coordination(
      prefix: "STALE",
      scope: "project:stale",
      repository_id: REPOSITORY_IDS.fetch(0),
      label: "stale-build",
      reserve: true
    )
    available = query.call(scope: "project:stale").value!.data.page.items.sole
    expect(available).to have_attributes(candidate_checkpoint_count: 0)

    submit_candidate(coordination, candidate_id: "CAN-DISC-STALE")

    stale = query.call(scope: "project:stale").value!.data.page.items.sole
    expect(stale).to have_attributes(
      change_set_id: coordination.dig(:ids, :change_set_id),
      candidate_checkpoint_count: 0
    )

    project_coordination(coordination.fetch(:ids))
    converged = query.call(scope: "project:stale").value!.data.page.items.sole
    expect(converged).to have_attributes(candidate_checkpoint_count: 1)
  end

  it "returns typed empty and invalid results without inferring a scope hierarchy" do
    empty = query.call(scope: "project:absent").value!
    invalid = query.call(
      scope: "project:absent",
      statuses: [ "active", "active" ],
      limit: 51
    ).value!

    expect(empty.data.page).to have_attributes(items: [], has_more: false)
    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
  end

  def create_coordination(prefix:, scope:, repository_id:, label:, checkpoint: false, reserve: false)
    register_repository(prefix:, scope:, repository_id:)
    ids = {
      change_set_id: "CS-#{prefix}-#{label}",
      work_item_id: "W-#{prefix}-#{label}",
      attempt_id: "A-#{prefix}-#{label}"
    }
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "cmd-#{prefix}-create",
      actor: { kind: "agent", id: "planner-#{prefix}" },
      change_set_id: ids.fetch(:change_set_id),
      goal: "Coordinate #{label}",
      acceptance_criteria: [ "The scoped coordination is discoverable" ]
    })
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "cmd-#{prefix}-work-item",
      actor: { kind: "agent", id: "planner-#{prefix}" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      repository_id:,
      goal: "Implement #{label}",
      acceptance_criteria: [ "The Attempt can checkpoint work" ]
    })
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "cmd-#{prefix}-activate",
      actor: { kind: "agent", id: "planner-#{prefix}" },
      change_set_id: ids.fetch(:change_set_id)
    })
    activation = change_set_events(ids.fetch(:change_set_id)).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "cmd-#{prefix}-acquire",
      actor: { kind: "agent", id: "agent-#{prefix}" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
    })

    coordination = { prefix:, repository_id:, ids: }
    coordination[:reservation] = reserve_write_set(coordination) if reserve || checkpoint
    submit_candidate(coordination, candidate_id: "CAN-#{prefix}-checkpoint") if checkpoint
    project_coordination(ids)
    coordination
  end

  def register_repository(prefix:, scope:, repository_id:)
    execute(Coordinator::Write::Operations::ExecuteRegisterRepository, {
      command_id: "cmd-#{prefix}-repository",
      actor: { kind: "agent", id: "repository-registrar" },
      repository_id:,
      scope:,
      repository_key: prefix.downcase,
      display_name: "#{prefix} repository",
      paths: [],
      remotes: []
    })
    event = event_store.read(
      streams.repository(repository_id),
      Coordinator::Write::EventQueries::REPOSITORY_REGISTRATION
    ).sole
    repository_projector.call(event)
  end

  def reserve_write_set(coordination)
    ids = coordination.fetch(:ids)
    path = "app/#{coordination.fetch(:prefix).downcase}.rb"
    resource_id = ResourceScenario.resolve(
      event_store:,
      repository_id: coordination.fetch(:repository_id),
      kind: "file",
      path:
    )
    execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "cmd-#{coordination.fetch(:prefix)}-reserve",
      actor: { kind: "agent", id: "agent-#{coordination.fetch(:prefix)}" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: coordination.fetch(:repository_id),
      base_commit_oid: "a" * 40,
      resources: [
        {
          resource_id:,
          base_blob_oid: "b" * 40
        }
      ],
      lease_duration_seconds: 900
    }).data
  end

  def submit_candidate(coordination, candidate_id:)
    ids = coordination.fetch(:ids)
    reservation = coordination.fetch(:reservation)
    path = "app/#{coordination.fetch(:prefix).downcase}.rb"
    execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, {
      command_id: "cmd-#{candidate_id}-submit",
      actor: { kind: "agent", id: "agent-#{coordination.fetch(:prefix)}" },
      candidate_id:,
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: coordination.fetch(:repository_id),
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid: "c" * 40,
      checkpoint_kind: "intermediate",
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |reference|
        {
          resource_id: reference.resource_id,
          lease_id: reference.lease_id,
          fencing_token: reference.fencing_token
        }
      end,
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [
          {
            status: "modified",
            old_path: path,
            new_path: path,
            old_blob_oid: "b" * 40,
            new_blob_oid: "d" * 40,
            old_mode: "100644",
            new_mode: "100644"
          }
        ]
      }
    })
  end

  def project_coordination(ids)
    events = [
      [ streams.change_set(ids.fetch(:change_set_id)), 1_103 ],
      [ streams.work_item(ids.fetch(:work_item_id)), 10 ],
      [ streams.attempt(ids.fetch(:attempt_id)), 40 ]
    ].flat_map do |stream, maximum_count|
      event_store.read(
        stream,
        Coordinator::Write::EventReadCriteria.new(
          event_types: Coordinator::Read::Contracts::CoordContextSourceEvent::EVENT_STREAMS.keys,
          maximum_count:,
          direction: :asc
        )
      )
    end
    events.sort_by(&:global_position).each { context_projector.call(_1) }
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def execute(operation_class, arguments)
    operation_class.new(event_store:).call(arguments).value!
  end
end
