# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CoordContextV1, :read_model, :event_store do
  subject(:projector) { described_class.new(source_loader:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:factory) { Coordinator::Write::EventFactory.new }
  let(:repository) { Coordinator::Read::Repositories::CoordContexts.new }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { SecureRandom.uuid_v7 }
  let(:work_item_id) { SecureRandom.uuid_v7 }
  let(:attempt_id) { SecureRandom.uuid_v7 }
  let(:agent_id) { "agent-a" }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:set_id) { SecureRandom.uuid_v7 }
  let(:intention_id) { SecureRandom.uuid_v7 }
  let(:resource_id) { SecureRandom.uuid_v7 }
  let(:source_loader) do
    Coordinator::Read::CoordContexts::SourceLoader.new(
      event_store:,
      submission_loader: Coordinator::Read::Candidates::SubmissionLoader.new(event_store:)
    )
  end

  it "atomically projects current definition facts with exact source identities and duplicate protection" do
    planning = planning_events
    planning.each { projector.call(_1) }
    2.times { projector.call(planning.last) }

    snapshot = repository.resolve(scope_kind: "work_item", scope_id: work_item_id)
    expect(snapshot.state.change_set).to have_attributes(
      change_set_id:, goal: "Coordinate this project", acceptance_criteria: [ "Agents do not overlap" ]
    )
    expect(snapshot.state.work_item_ids).to eq([ work_item_id ])
    expect(snapshot.state.work_items.sole).to have_attributes(work_item_id:, repository_id:, status: "planned")
    expect(snapshot.source_positions.length).to eq(2)
    expect(processed_events.count).to eq(2)
    expect(Coordinator::Read::CoordContextScope.find_by!(scope_kind: "work_item", scope_id: work_item_id).updated_at)
      .to eq(planning.last.created_at)
    expect(snapshot.state.change_set.created_at).to eq(timestamp(planning.first))
    expect(snapshot.state.work_items.sole.created_at).to eq(timestamp(planning.fetch(3)))
  end

  it "keeps the projection available when a broad type filter encounters a superseded schema" do
    event = planning_events.first
    event.metadata["schema_version"] = 1

    expect { projector.call(event) }.not_to change(Coordinator::Read::ProcessedProjectionEvent, :count)
  end

  it "converges when definition-component deliveries surround the complete WorkItem definition" do
    planning = planning_events
    change_definition = planning.fetch(2)
    work_definition = planning.last
    components = [ planning.first, planning.fetch(3), planning.fetch(4) ]
    [ change_definition, *components, work_definition ].each { projector.call(_1) }
    first_document = Coordinator::Read::CoordContext.find(change_set_id).document

    ReadModelTestSafety.clean!
    [ change_definition, work_definition, *components.reverse ].each { projector.call(_1) }

    expect(Coordinator::Read::CoordContext.find(change_set_id).document).to eq(first_document)
  end

  it "converges abandonment and requeue in either cross-stream order with native occurrence times" do
    events = active_attempt_events
    reason = "The agent yielded this WorkItem."
    abandoned = append(streams.attempt(attempt_id),
      Coordinator::Write::Events::AttemptAbandonedV3.new(attempt_id:, reason:)).sole
    requeued = append(streams.work_item(work_item_id),
      Coordinator::Write::Events::WorkItemRequeuedV2.new(
        change_set_id:, work_item_id:, attempt_id:, agent_id:, reason:
      )).sole

    events.each { projector.call(_1) }
    [ abandoned, requeued, abandoned, requeued ].each { projector.call(_1) }
    first_document = Coordinator::Read::CoordContext.find(change_set_id).document
    assert_abandoned_context(abandoned, reason:)

    ReadModelTestSafety.clean!
    events.each { projector.call(_1) }
    [ requeued, abandoned ].each { projector.call(_1) }

    expect(Coordinator::Read::CoordContext.find(change_set_id).document).to eq(first_document)
    assert_abandoned_context(abandoned, reason:)
  end

  it "projects exact ownership, Attempt bases and current work-intention lifecycle evidence" do
    active_attempt_events.each { projector.call(_1) }
    declared = intention_events
    declared.each { projector.call(_1) }

    context = repository.resolve(scope_kind: "attempt", scope_id: attempt_id).state
    expect(context.change_set.status).to eq("active")
    expect(context.work_items.sole).to have_attributes(
      status: "acquired", active_attempt_id: attempt_id, active_agent_id: agent_id
    )
    expect(context.attempts.sole).to have_attributes(
      status: "started",
      base_snapshots: [ Coordinator::Write::RepositorySnapshotV1.new(
        repository_id:, object_format: "sha1", commit_oid: "a" * 40
      ) ]
    )
    intention = context.attempts.sole.work_intention_set.intentions.sole
    expect(intention).to have_attributes(
      intention_id:, resource_id:, resource_path: "app/models/invoice.rb",
      mode: "shared", purpose: "Improve invoice validation", context: "Parallel development is permitted",
      fencing_token: 1
    )

    renewed = append(streams.resource_work_intention(intention_id),
      Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
        intention_id:, resource_id:, fencing_token: 1, expires_at: "2026-12-01T01:00:00.000000Z"
      )).sole
    projector.call(renewed)
    withdrawn = append(streams.resource_work_intention(intention_id),
      Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1.new(
        intention_id:, resource_id:, fencing_token: 1, reason: "Checkpoint published"
      )).sole
    2.times { projector.call(withdrawn) }

    set = repository.resolve(scope_kind: "attempt", scope_id: attempt_id).state.attempts.sole.work_intention_set
    expect(set).to have_attributes(
      intention_set_id: set_id,
      policy_version: "coordinator-work-intention/v1",
      declared_at: timestamp(declared.fetch(1)),
      last_renewed_at: timestamp(renewed),
      expires_at: "2026-12-01T01:00:00.000000Z",
      withdrawn_at: timestamp(withdrawn)
    )
    expect(set.to_h.keys & %i[active fresh pending]).to be_empty

    history = Coordinator::Read::AttemptHistory.find(attempt_id)
    expect(history.work_intention_set_last_renewed_event.fetch("event_id")).to eq(renewed.id)
    expect(history.work_intention_set_withdrawal_event.fetch("event_id")).to eq(withdrawn.id)
    expect(history.updated_at).to eq(withdrawn.created_at)
  end

  it "rebuilds projection-owned Attempt history when its projection version advances" do
    create(:coordinator_read_attempt_history, :with_work_intention_set,
      attempt_id:, change_set_id:, work_item_id:,
      projection_version: described_class::PROJECTION.version - 1)

    active_attempt_events.each { projector.call(_1) }

    history = Coordinator::Read::AttemptHistory.find(attempt_id)
    expect(history).to have_attributes(
      projection_version: described_class::PROJECTION.version, agent_id:, status: "started",
      work_intention_set_id: nil, work_intention_set_intentions: []
    )
  end

  it "retains the latest observed Candidate checkpoint while Candidate history remains separate" do
    active_attempt_events.each { projector.call(_1) }
    intention_events
    first = candidate_events(checkpoint_kind: "intermediate", head_character: "b")
    second = candidate_events(checkpoint_kind: "handoff", head_character: "e")
    [ first.last, second.last ].each { projector.call(_1) }

    checkpoint = repository.resolve(scope_kind: "attempt", scope_id: attempt_id).state.candidate_checkpoints.sole
    expect(checkpoint).to have_attributes(
      candidate_id: second.last.stream.stream_id, attempt_id:, checkpoint_kind: "handoff",
      head_commit_oid: "e" * 40, manifest_digest: "sha256:#{'e' * 64}"
    )
    expect(checkpoint.candidate_event.event_id).to eq(second.last.id)
  end

  it "serves observed final-Candidate context before completion, then converges lean terminal facts" do
    active_attempt_events.each { projector.call(_1) }
    intention_events
    candidate = candidate_events(checkpoint_kind: "final", head_character: "e").last
    projector.call(candidate)
    before_completion = Coordinator::Read::Queries::CoordContext.new.call(attempt_id:).value!
    expect(before_completion.data.context.work_items.sole.status).to eq("acquired")

    candidate_id = candidate.stream.stream_id
    selected, output, completed = append(streams.work_item(work_item_id),
      Coordinator::Write::Events::WorkItemCandidateSelectedV2.new(
        change_set_id:, work_item_id:, attempt_id:, candidate_id:, candidate_event: reference(candidate)
      ),
      Coordinator::Write::Events::WorkItemOutputRecordedV1.new(
        work_item_id:, output_kind: "artifact", output_key: "invoice-validation"
      ),
      Coordinator::Write::Events::WorkItemCompletedV2.new(work_item_id:))
    attempt_completed = append(streams.attempt(attempt_id),
      Coordinator::Write::Events::AttemptCompletedV2.new(attempt_id:)).sole
    change_completed = append(streams.change_set(change_set_id),
      Coordinator::Write::Events::ChangeSetCompletedV2.new(change_set_id:)).sole
    [ selected, output, completed, attempt_completed, change_completed ].each { projector.call(_1) }

    converged = Coordinator::Read::Queries::CoordContext.new.call(change_set_id:).value!
    expect(converged.status).to eq("ok")
    expect(converged.data.context.change_set).to have_attributes(
      status: "completed", completed_at: timestamp(change_completed)
    )
    expect(converged.data.context.work_items.sole).to have_attributes(
      status: "completed", selected_candidate_id: candidate_id, completed_at: timestamp(completed),
      produced_outputs: [ Coordinator::Write::WorkItemOutputV1.new(kind: "artifact", key: "invoice-validation") ]
    )
    expect(converged.data.context.attempts.sole).to have_attributes(
      status: "completed", selected_candidate_id: candidate_id, completed_at: timestamp(attempt_completed)
    )
    expect(converged.to_h).not_to include(:projection_status, :fresh, :pending)
  end

  it "removes an observed dependency blocker before its independently projected readiness fact" do
    producer_id = work_item_id
    consumer_id = SecureRandom.uuid_v7
    dependency_id = SecureRandom.uuid_v7
    planning_events.each { projector.call(_1) }
    work_item_definition_events(consumer_id).each { projector.call(_1) }
    dependency = {
      change_set_id:, dependency_id:, producer_work_item_id: producer_id,
      consumer_work_item_id: consumer_id, dependency_kind: "requires_completion", required_output: nil
    }
    declared = append(streams.work_item(consumer_id),
      Coordinator::Write::Events::WorkItemDependencyDeclaredV2.new(dependency)).sole
    activated = append(streams.change_set(change_set_id),
      Coordinator::Write::Events::ChangeSetActivatedV2.new(change_set_id:)).sole
    [ declared, activated ].each { projector.call(_1) }
    blocked = Coordinator::Read::Queries::CoordContext.new.call(work_item_id: consumer_id).value!
    expect(blocked.data.blockers.sole.dependency_id).to eq(dependency_id)

    completed_source = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7, type: "WorkItemCompleted",
      stream_context: "DevelopmentExecution", stream_name: "WorkItem",
      stream_id: producer_id, stream_revision: 8
    )
    satisfied = append(streams.work_item(consumer_id),
      Coordinator::Write::Events::WorkItemDependencySatisfiedV2.new(dependency.merge(source: completed_source))).sole
    projector.call(satisfied)

    observed = Coordinator::Read::Queries::CoordContext.new.call(work_item_id: consumer_id).value!
    expect(observed.data.blockers).to be_empty
    expect(observed.data.context.work_items.find { _1.work_item_id == consumer_id }.status).to eq("planned")
    expect(observed.data.context.dependencies.sole).to have_attributes(
      source_event: completed_source, satisfied_at: timestamp(satisfied)
    )

    ready = append(streams.work_item(consumer_id),
      Coordinator::Write::Events::WorkItemMadeReadyV2.new(
        change_set_id:, work_item_id: consumer_id, readiness_decision_id: SecureRandom.uuid_v7,
        reason: "dependencies_satisfied"
      )).sole
    projector.call(ready)
    converged = Coordinator::Read::Queries::CoordContext.new.call(work_item_id: consumer_id).value!
    expect(converged.data.blockers).to be_empty
    expect(converged.next_actions).to be_empty
  end

  def planning_events
    append(streams.change_set(change_set_id),
      Coordinator::Write::Events::ChangeSetCreatedV2.new(change_set_id:),
      Coordinator::Write::Events::ChangeSetGoalDefinedV1.new(change_set_id:, goal: "Coordinate this project"),
      Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV2.new(
        change_set_id:, acceptance_criteria: [ "Agents do not overlap" ]
      )) + work_item_definition_events(work_item_id)
  end

  def work_item_definition_events(id)
    append(streams.work_item(id),
      Coordinator::Write::Events::WorkItemCreatedV2.new(work_item_id: id),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(change_set_id:, work_item_id: id),
      Coordinator::Write::Events::WorkItemAssignedToRepositoryV1.new(work_item_id: id, repository_id:),
      Coordinator::Write::Events::WorkItemGoalDefinedV1.new(work_item_id: id, goal: "Implement verifiable work"),
      Coordinator::Write::Events::WorkItemAcceptanceCriteriaDefinedV1.new(
        work_item_id: id, acceptance_criteria: [ "The work is verifiable" ]
      ),
      Coordinator::Write::Events::WorkItemCompetitiveModeSelectedV1.new(work_item_id: id, competitive_mode: false))
  end

  def active_attempt_events
    planning_events +
      append(streams.change_set(change_set_id),
        Coordinator::Write::Events::ChangeSetActivatedV2.new(change_set_id:)) +
      append(streams.work_item(work_item_id),
        Coordinator::Write::Events::WorkItemMadeReadyV2.new(
          change_set_id:, work_item_id:, readiness_decision_id: SecureRandom.uuid_v7, reason: "change_set_activated"
        ),
        Coordinator::Write::Events::WorkItemAcquiredV2.new(change_set_id:, work_item_id:, attempt_id:, agent_id:)) +
      append(streams.attempt(attempt_id),
        Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id:),
        Coordinator::Write::Events::AttemptAssignedToWorkItemV1.new(attempt_id:, change_set_id:, work_item_id:),
        Coordinator::Write::Events::AttemptAssignedToAgentV1.new(attempt_id:, agent_id:),
        Coordinator::Write::Events::AttemptBaseSnapshotRecordedV1.new(
          attempt_id:, repository_id:, object_format: "sha1", commit_oid: "a" * 40
        ),
        Coordinator::Write::Events::AttemptStartedV2.new(attempt_id:))
  end

  def intention_events
    append(streams.resource(resource_id),
      Coordinator::Write::Events::ResourceIdentityV2::Registered.new(
        resource_id:, repository_id:, kind: "file", normalized_path: "app/models/invoice.rb"
      )) +
      append(streams.work_intention_set(set_id),
        Coordinator::Write::Events::WorkIntentionSetCreatedV1.new(
          set_id:, attempt_id:, work_item_id:, change_set_id:, repository_id:
        ),
        Coordinator::Write::Events::WorkIntentionAddedToSetV1.new(set_id:, intention_id:, resource_id:)) +
      append(streams.resource_work_intention(intention_id),
        Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1.new(
          intention_id:, set_id:, resource_id:, repository_id:, change_set_id:, work_item_id:, attempt_id:, agent_id:,
          mode: "shared", purpose: "Improve invoice validation", context: "Parallel development is permitted",
          object_format: "sha1", base_commit_oid: "a" * 40, base_blob_oid: "b" * 40, fencing_token: 1,
          expires_at: "2026-12-01T00:00:00.000000Z"
        ))
  end

  def candidate_events(checkpoint_kind:, head_character:)
    candidate_id = SecureRandom.uuid_v7
    command_id = SecureRandom.uuid_v7
    command = candidate_submission_command(candidate_id:, command_id:, checkpoint_kind:, head_character:)
    input_digest = Coordinator::Write::CommandInputDigest.new.call(command)
    append(streams.command(command_id),
      Coordinator::Write::Events::CommandRegisteredV1.new(
        command_id:, request_id: 1, tool_name: "candidate_submit"
      ),
      command_id:,
      metadata_class: Coordinator::Write::Metadata::CanonicalCommandV1,
      metadata_attributes: {
        policy_version: "coordination-task/v3", canonical_input_digest: input_digest
      },
      markers: [ "command:#{command_id}" ])
    task_id = SecureRandom.uuid_v7
    append(streams.coordination_task(task_id),
      Coordinator::Write::Events::CoordinationTaskSubmittedV3.new(
        task_id:, command_id:, tool_name: "candidate_submit",
        command_input: Coordinator::Write::CommandInputDigest.new.document(command),
        poll_interval_ms: 500, ttl_ms: nil
      ), command_id:, markers: [ "command:#{command_id}", "task:#{task_id}" ])
    manifest = Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
      candidate_id:, evidence_revision: 1,
      files: [ Coordinator::Write::Candidates::ManifestFileV1.new(
        status: "modified", old_path: "app/models/invoice.rb", new_path: "app/models/invoice.rb",
        old_blob_oid: "b" * 40, new_blob_oid: head_character * 40, old_mode: "100644", new_mode: "100644"
      ) ]
    )
    definition = append(streams.candidate(candidate_id),
      Coordinator::Write::Events::CandidateCreatedV1.new(candidate_id:),
      Coordinator::Write::Events::CandidateAssignedToAttemptV1.new(candidate_id:, attempt_id:, work_item_id:, change_set_id:),
      Coordinator::Write::Events::CandidateAssignedToRepositoryV1.new(candidate_id:, repository_id:),
      Coordinator::Write::Events::CandidateTargetBranchSelectedV1.new(candidate_id:, target_branch: "main"),
      Coordinator::Write::Events::CandidateCommitRangeDeclaredV1.new(
        candidate_id:, object_format: "sha1", base_commit_oid: "a" * 40, head_commit_oid: head_character * 40
      ),
      Coordinator::Write::Events::CandidateCheckpointKindSelectedV1.new(candidate_id:, checkpoint_kind:),
      Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1.new(candidate_id:, intention_set_id: set_id),
      command_id:)
    captured = append(streams.candidate(candidate_id), manifest,
      command_id:,
      extra_metadata: {
        "manifest_digest" => "sha256:#{head_character * 64}",
        "policy_version" => "candidate-change-manifest/v1",
        "collector" => { "kind" => "agent", "id" => agent_id, "collector_version" => "git-evidence-v1" }
      })
    submitted = append(streams.candidate(candidate_id),
      Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:), command_id:)
    definition + captured + submitted
  end

  def candidate_submission_command(candidate_id:, command_id:, checkpoint_kind:, head_character:)
    files = [ Coordinator::Write::Candidates::ManifestFileV1.new(
      status: "modified", old_path: "app/models/invoice.rb", new_path: "app/models/invoice.rb",
      old_blob_oid: "b" * 40, new_blob_oid: head_character * 40, old_mode: "100644", new_mode: "100644"
    ) ]
    Coordinator::Write::Commands::SubmitCandidate.new(
      command_id:,
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: agent_id),
      candidate_id:, change_set_id:, work_item_id:, attempt_id:, repository_id:, target_branch: "main",
      object_format: "sha1", base_commit_oid: "a" * 40, head_commit_oid: head_character * 40,
      checkpoint_kind:, intention_set_id: set_id,
      intentions: [ Coordinator::Write::WorkIntentionFencedReferenceV1.new(
        intention_id:, resource_id:, fencing_token: 1
      ) ],
      manifest: Coordinator::Write::Candidates::ChangeManifestV1.new(
        policy_version: Coordinator::Write::Candidates::ChangeManifestDocumentV1::SCHEMA,
        digest: "sha256:#{head_character * 64}", files:,
        collector: Coordinator::Write::Candidates::EvidenceCollectorV1.new(
          kind: "agent", id: agent_id, collector_version: "git-evidence-v1"
        )
      ),
      build_context: nil,
      actual_resources: [ Coordinator::Write::Candidates::ActualResourceV2.new(
        kind: "file", path: "app/models/invoice.rb", base_blob_oid: "b" * 40
      ) ]
    )
  end

  def append(stream, *facts, extra_metadata: {}, command_id: "cmd-coord-context-projection",
             metadata_class: Coordinator::Write::EventMetadata, metadata_attributes: {}, markers: [])
    metadata = Coordinator::Write::EventMetadata.new(
      command_id:, actor_kind: "agent", actor_id: agent_id,
      recorded_by: "coordinator", policy_version: "coordinator-work-intention/v1"
    )
    metadata = metadata_class.new(**metadata.to_h.merge(metadata_attributes))
    events = facts.map do |fact|
      event = factory.build!(event: fact, event_id: SecureRandom.uuid_v7, metadata:, markers:, correlation_id:)
      event.metadata.merge!(extra_metadata)
      event
    end
    event_store.append(stream, events)
  end

  def timestamp(event)
    event.created_at.utc.iso8601(6)
  end

  def reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id, type: event.type, stream_context: event.stream.context,
      stream_name: event.stream.stream_name, stream_id: event.stream.stream_id, stream_revision: event.stream_revision
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(projection_name: "coord_context")
  end

  def assert_abandoned_context(event, reason:)
    state = repository.resolve(scope_kind: "work_item", scope_id: work_item_id).state
    expect(state.work_items.sole).to have_attributes(status: "ready", active_attempt_id: nil, active_agent_id: nil)
    expect(state.attempts.sole).to have_attributes(
      attempt_id:, agent_id:, status: "abandoned", abandonment_reason: reason, abandoned_at: timestamp(event)
    )
    history = repository.attempt_page(work_item_id:, after_authorized_global_position: nil, limit: 1).items.sole
    expect(history).to have_attributes(
      attempt_id:, work_item_id:, agent_id:, status: "abandoned", abandonment_reason: reason, terminal_at: timestamp(event)
    )
  end
end
