# frozen_string_literal: true

RSpec.describe "history migration planning entity transformers", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planning_dispatcher) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "legacy-change-set" }
  let(:work_item_id) { "legacy-work-item" }
  let(:attempt_id) { "legacy-attempt" }

  it "splits ChangeSet identity, goal, release relation, and completion without occurrence copies" do
    release_stream = stream("DevelopmentIntegration", "ReleaseSet", "legacy-release-set")
    persist_raw(release_stream, type: "LegacyReleaseSetPrepared")
    release_completion = persist_raw(release_stream, type: "ReleaseSetCompleted")
    change_set_stream = stream("DevelopmentPlanning", "ChangeSet", change_set_id)
    created = persist_payload(
      change_set_stream,
      Coordinator::Write::Events::ChangeSetCreatedV1.new(
        change_set_id:,
        goal: "Migrate planning history",
        created_at: "2001-01-01T00:00:00.000000Z"
      )
    )
    completion = persist_payload(
      change_set_stream,
      Coordinator::Write::Events::ChangeSetCompletedV1.new(
        change_set_id:,
        work_item_completions: [ completion_evidence ],
        release_set_completion_event: event_reference(release_completion),
        rule_version: "change-set-completion/v1",
        completed_at: "2001-01-02T00:00:00.000000Z"
      )
    )

    created_facts = transform(created, upper_position: completion.global_position).value!
    completed_facts = transform(completion, upper_position: completion.global_position).value!

    expect(created_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ChangeSetCreatedV2,
      Coordinator::Write::Events::ChangeSetGoalDefinedV1
    ])
    expect(completed_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::ChangeSetReleaseSetLinkedV1,
      Coordinator::Write::Events::ChangeSetCompletedV2
    ])
    expect((created_facts + completed_facts).map(&:target_stream).uniq.one?).to be(true)
    expect(created_facts.first.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(completed_facts.first.event.release_set_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(completed_facts.map { _1.metadata_extension.policy_version }.uniq).to eq(
      [ "change-set-completion/v1" ]
    )
    expect((created_facts + completed_facts).flat_map { _1.event.to_h.keys }).not_to include(
      :created_at,
      :completed_at,
      :work_item_completions,
      :release_set_completion_event
    )
  end

  it "splits WorkItem properties and migrates its separately recorded membership exactly once" do
    persist_raw(stream("DevelopmentPlanning", "Repository", repository_id), type: "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    work_item_stream = stream("DevelopmentExecution", "WorkItem", work_item_id)
    created = persist_payload(
      work_item_stream,
      Coordinator::Write::Events::WorkItemCreatedV1.new(
        work_item_id:,
        change_set_id:,
        repository_id:,
        goal: "Transform WorkItem facts",
        acceptance_criteria: [ "Identity and properties are distinct" ],
        competitive_mode: false,
        created_at: "2001-02-01T00:00:00.000000Z"
      )
    )
    membership = persist_payload(
      stream("DevelopmentPlanning", "ChangeSet", change_set_id),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV1.new(
        work_item_id:,
        change_set_id:,
        added_at: "2001-02-01T00:01:00.000000Z"
      )
    )

    created_facts = transform(created, upper_position: membership.global_position).value!
    membership_facts = transform(membership, upper_position: membership.global_position).value!
    all_facts = created_facts + membership_facts

    expect(created_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::WorkItemCreatedV2,
      Coordinator::Write::Events::WorkItemAssignedToRepositoryV1,
      Coordinator::Write::Events::WorkItemGoalDefinedV1,
      Coordinator::Write::Events::WorkItemAcceptanceCriteriaDefinedV1,
      Coordinator::Write::Events::WorkItemCompetitiveModeSelectedV1
    ])
    expect(membership_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2
    ])
    expect(all_facts.count { _1.event.is_a?(Coordinator::Write::Events::WorkItemAddedToChangeSetV2) }).to eq(1)
    expect(all_facts.map(&:target_stream).uniq.one?).to be(true)
    expect(all_facts.first.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(all_facts.flat_map { _1.event.to_h.keys }).not_to include(:created_at, :added_at)
  end

  it "rebinds dependency identities and source evidence to target WorkItem facts" do
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    producer_id = "legacy-producer"
    consumer_id = "legacy-consumer"
    producer_stream = stream("DevelopmentExecution", "WorkItem", producer_id)
    consumer_stream = stream("DevelopmentExecution", "WorkItem", consumer_id)
    persist_raw(producer_stream, type: "WorkItemCreated")
    persist_raw(consumer_stream, type: "WorkItemCreated")
    declaration = persist_payload(
      stream("DevelopmentPlanning", "ChangeSet", change_set_id),
      Coordinator::Write::Events::WorkItemDependencyDeclaredV1.new(
        change_set_id:,
        dependency_id: "legacy-dependency",
        producer_work_item_id: producer_id,
        consumer_work_item_id: consumer_id,
        dependency_kind: "requires_completion",
        required_output: nil,
        declared_at: "2001-03-01T00:00:00.000000Z"
      ),
      markers: [ "dependency:legacy-dependency" ]
    )
    source_completion = persist_payload(
      producer_stream,
      Coordinator::Write::Events::WorkItemCompletedV1.new(
        change_set_id:,
        work_item_id: producer_id,
        attempt_id: "legacy-producer-attempt",
        candidate_id: "legacy-producer-candidate",
        candidate_event: arbitrary_reference,
        produced_outputs: [],
        rule_version: "work-item-completion/v1",
        completed_at: "2001-03-01T00:01:00.000000Z"
      )
    )
    satisfaction = persist_payload(
      stream("DevelopmentPlanning", "ChangeSet", change_set_id),
      Coordinator::Write::Events::WorkItemDependencySatisfiedV1.new(
        change_set_id:,
        dependency_id: "legacy-dependency",
        producer_work_item_id: producer_id,
        consumer_work_item_id: consumer_id,
        dependency_kind: "requires_completion",
        required_output: nil,
        source_event: event_reference(source_completion),
        rule_version: "dependency-satisfaction/v1",
        satisfied_at: "2001-03-01T00:02:00.000000Z"
      ),
      markers: [ "dependency:legacy-dependency" ]
    )
    upper_position = satisfaction.global_position
    expect(plan(source_completion, upper_position:)).to be_success

    declared_fact = transform(declaration, upper_position:).value!.sole
    satisfied_fact = transform(satisfaction, upper_position:).value!.sole

    expect(declared_fact.event.dependency_id).to eq(declaration.id)
    expect(satisfied_fact.event.dependency_id).to eq(declaration.id)
    expect(satisfied_fact.event.source).to have_attributes(
      type: "WorkItemCompleted",
      stream_context: "DevelopmentExecution",
      stream_name: "WorkItem"
    )
    expect(satisfied_fact.event.source.event_id).not_to eq(source_completion.id)
    expect(satisfied_fact.event.source.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(satisfied_fact.event.consumer_work_item_id).to eq(satisfied_fact.target_stream.stream_id)
    expect(satisfied_fact.metadata_extension.policy_version).to eq("dependency-satisfaction/v1")
  end

  it "extracts WorkItem outputs and carries the deciding rule in metadata" do
    work_item_stream = stream("DevelopmentExecution", "WorkItem", work_item_id)
    persist_raw(work_item_stream, type: "WorkItemCreated")
    completion = persist_payload(
      work_item_stream,
      Coordinator::Write::Events::WorkItemCompletedV1.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        candidate_id: "legacy-candidate",
        candidate_event: arbitrary_reference,
        produced_outputs: [
          Coordinator::Write::WorkItemOutputV1.new(kind: "artifact", key: "review-report")
        ],
        rule_version: "work-item-completion/v1",
        completed_at: "2001-04-01T00:00:00.000000Z"
      )
    )

    facts = transform(completion, upper_position: completion.global_position).value!

    expect(facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::WorkItemOutputRecordedV1,
      Coordinator::Write::Events::WorkItemCompletedV2
    ])
    expect(facts.first.event).to have_attributes(
      output_kind: "artifact",
      output_key: "review-report"
    )
    expect(facts.map { _1.metadata_extension.policy_version }.uniq).to eq([
      "work-item-completion/v1"
    ])
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(
      :candidate_event,
      :candidate_id,
      :completed_at,
      :rule_version
    )
  end

  it "rebinds the WorkItem readiness, acquisition, and requeue lifecycle" do
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    work_item_stream = stream("DevelopmentExecution", "WorkItem", work_item_id)
    attempt_stream = stream("DevelopmentExecution", "Attempt", attempt_id)
    persist_raw(work_item_stream, type: "WorkItemCreated")
    persist_raw(attempt_stream, type: "AttemptAuthorized")
    ready = persist_payload(
      work_item_stream,
      Coordinator::Write::Events::WorkItemMadeReadyV1.new(
        change_set_id:,
        work_item_id:,
        readiness_decision_id: "internal:legacy-readiness:digest",
        reason: "change_set_activated",
        made_ready_at: "2001-04-02T00:00:00.000000Z"
      )
    )
    acquired = persist_payload(
      work_item_stream,
      Coordinator::Write::Events::WorkItemAcquiredV1.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        agent_id: "agent-one",
        acquired_at: "2001-04-02T00:01:00.000000Z"
      )
    )
    requeued = persist_payload(
      work_item_stream,
      Coordinator::Write::Events::WorkItemRequeuedV1.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        agent_id: "agent-one",
        reason: "Attempt interrupted",
        requeued_at: "2001-04-02T00:02:00.000000Z"
      )
    )
    upper_position = requeued.global_position

    facts = [ ready, acquired, requeued ].map do |event|
      transform(event, upper_position:).value!.sole
    end

    expect(facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::WorkItemMadeReadyV2,
      Coordinator::Write::Events::WorkItemAcquiredV2,
      Coordinator::Write::Events::WorkItemRequeuedV2
    ])
    expect(facts.map(&:target_stream).uniq.one?).to be(true)
    expect(facts.first.event.readiness_decision_id).to eq(ready.id)
    expect(facts.drop(1).map { _1.event.attempt_id }.uniq).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(facts.flat_map { _1.event.to_h.keys }).not_to include(
      :made_ready_at,
      :acquired_at,
      :requeued_at
    )
  end

  it "splits Attempt authorization assignments and base snapshots from terminal facts" do
    persist_raw(stream("DevelopmentPlanning", "Repository", repository_id), type: "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id), type: "WorkItemCreated")
    attempt_stream = stream("DevelopmentExecution", "Attempt", attempt_id)
    authorized = persist_payload(
      attempt_stream,
      Coordinator::Write::Events::AttemptAuthorizedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        agent_id: "agent-one",
        base_snapshots: [
          Coordinator::Write::RepositorySnapshotV1.new(
            repository_id:,
            object_format: "sha1",
            commit_oid: "a" * 40
          )
        ],
        authorized_at: "2001-05-01T00:00:00.000000Z"
      )
    )
    started = persist_payload(
      attempt_stream,
      Coordinator::Write::Events::AttemptStartedV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:,
        started_at: "2001-05-01T00:01:00.000000Z"
      )
    )
    abandoned = persist_payload(
      attempt_stream,
      Coordinator::Write::Events::AttemptAbandonedV2.new(
        change_set_id:,
        work_item_id:,
        attempt_id:,
        agent_id: "agent-one",
        reason: "Work was superseded",
        lease_set_id: nil,
        released_leases: [],
        untouched_resource_ids: [],
        abandoned_at: "2001-05-01T00:02:00.000000Z"
      )
    )
    upper_position = abandoned.global_position

    authorized_facts = transform(authorized, upper_position:).value!
    started_fact = transform(started, upper_position:).value!.sole
    abandoned_fact = transform(abandoned, upper_position:).value!.sole

    expect(authorized_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::AttemptAuthorizedV2,
      Coordinator::Write::Events::AttemptAssignedToWorkItemV1,
      Coordinator::Write::Events::AttemptAssignedToAgentV1,
      Coordinator::Write::Events::AttemptBaseSnapshotRecordedV1
    ])
    expect(authorized_facts.map(&:target_stream).uniq.one?).to be(true)
    expect(authorized_facts.first.target_stream.stream_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(authorized_facts.last.event.repository_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(started_fact.event.to_h).to eq(attempt_id: started_fact.target_stream.stream_id)
    expect(abandoned_fact.event.to_h).to eq(
      attempt_id: abandoned_fact.target_stream.stream_id,
      reason: "Work was superseded"
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

  def plan(source_event, upper_position:)
    planning_dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def persist_payload(target_stream, payload, markers: [])
    persist_raw(
      target_stream,
      type: payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      markers:
    )
  end

  def persist_raw(target_stream, type:, data: {}, schema_version: 1, markers: [])
    event_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => "legacy-command",
            "actor_kind" => "agent",
            "actor_id" => "legacy-agent",
            "recorded_by" => "coordinator"
          },
          markers:,
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end

  def stream(context, stream_name, stream_id)
    Coordinator::Write::StreamReference.new(context:, stream_name:, stream_id:)
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

  def arbitrary_reference
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "legacy-candidate",
      stream_revision: 0
    )
  end

  def completion_evidence
    reference = arbitrary_reference
    Coordinator::Write::ChangeSetCompletions::WorkItemEvidenceV1.new(
      change_set_id:,
      work_item_id:,
      repository_id:,
      attempt_id:,
      candidate_id: "legacy-candidate",
      candidate_event: reference,
      selected_event: reference,
      completed_event: reference,
      completed_at: "2001-01-02T00:00:00.000000Z"
    )
  end
end
