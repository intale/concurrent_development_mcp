# frozen_string_literal: true

RSpec.describe "post-remodel history migration planning transformers", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planning_dispatcher) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:change_set_id) { "source-change-set" }
  let(:work_item_id) { "source-work-item" }
  let(:attempt_id) { "source-attempt" }
  let(:candidate_id) { "source-candidate" }
  let(:intention_set_id) { SecureRandom.uuid_v7 }

  it "rebinds post-remodel WorkItem and Attempt relationships instead of retaining source identities" do
    seed_execution_relationships
    attempt_stream = stream("DevelopmentExecution", "Attempt", attempt_id)
    persist_payload(attempt_stream, Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id:))
    assignment = persist_payload(
      attempt_stream,
      Coordinator::Write::Events::AttemptAssignedToWorkItemV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:
      )
    )
    acquired = persist_payload(
      stream("DevelopmentExecution", "WorkItem", work_item_id),
      Coordinator::Write::Events::WorkItemAcquiredV2.new(
        work_item_id:,
        change_set_id:,
        attempt_id:,
        agent_id: "codex"
      )
    )
    upper_position = acquired.global_position

    assignment_fact = transform(assignment, upper_position:).value!.sole
    acquired_fact = transform(acquired, upper_position:).value!.sole

    expect(assignment_fact.event).to be_a(Coordinator::Write::Events::AttemptAssignedToWorkItemV1)
    expect(acquired_fact.event).to be_a(Coordinator::Write::Events::WorkItemAcquiredV2)
    expect(assignment_fact.event.attempt_id).to eq(acquired_fact.event.attempt_id)
    expect(assignment_fact.event.work_item_id).to eq(acquired_fact.event.work_item_id)
    expect(assignment_fact.event.change_set_id).to eq(acquired_fact.event.change_set_id)
    expect([
      acquired_fact.event.attempt_id,
      acquired_fact.event.work_item_id,
      acquired_fact.event.change_set_id
    ]).to all(match(Coordinator::Shared::Types::UUID_V7_PATTERN))
    expect(acquired_fact.event.to_h.values).not_to include(attempt_id, work_item_id, change_set_id)
    expect(acquired_fact.metadata_extension.attributed_actor).to have_attributes(
      kind: "agent",
      id: "codex"
    )
  end

  it "reconstructs Candidate context, remaps its head, and preserves evidence metadata" do
    seed_candidate_relationships
    candidate_events = persist_candidate_history
    manifest = candidate_events.fetch(:manifest)
    submitted = candidate_events.fetch(:submitted)
    head = persist_payload(
      stream("DevelopmentIntegration", "CandidateHead", SecureRandom.uuid_v7),
      Coordinator::Write::Events::CandidateHeadRegisteredV2.new(
        registry_id: SecureRandom.uuid_v7,
        candidate_id:,
        attempt_id:,
        repository_id:,
        object_format: "sha1",
        head_commit_oid: "b" * 40
      ),
      metadata: {
        "marker_codec_version" => Coordinator::Write::Candidates::HeadIdentityBuilder::MARKER_CODEC_VERSION
      }
    )
    upper_position = head.global_position

    manifest_fact = transform(manifest, upper_position:).value!.sole
    submitted_fact = transform(submitted, upper_position:).value!.sole
    head_fact = transform(head, upper_position:).value!.sole
    candidate_facts = candidate_events.values.map do |event|
      transform(event, upper_position:).value!.sole
    end

    expect(manifest_fact.event).to be_a(Coordinator::Write::Events::CandidateChangeManifestCapturedV2)
    expect(manifest_fact.metadata_extension).to have_attributes(
      manifest_digest: "sha256:#{'c' * 64}",
      policy_version: "candidate-manifest/v2"
    )
    expect(manifest_fact.metadata_extension.collector).to have_attributes(
      kind: "agent",
      id: "codex",
      collector_version: "1"
    )
    expect(submitted_fact.event.candidate_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(submitted_fact.markers).to include(
      "candidate:#{submitted_fact.event.candidate_id}",
      a_string_matching(/\Aattempt:[0-9a-f-]{36}\z/),
      a_string_matching(/\Awork-intention-set:[0-9a-f-]{36}\z/)
    )
    expect(head_fact.event).to have_attributes(
      candidate_id: submitted_fact.event.candidate_id,
      object_format: "sha1",
      head_commit_oid: "b" * 40
    )
    expect(head_fact.event.registry_id).to eq(head_fact.target_stream.stream_id)
    expect(head_fact.event.attempt_id).not_to eq(attempt_id)
    expect(head_fact.event.repository_id).not_to eq(repository_id)
    expect(candidate_facts.map { _1.event.class }).to contain_exactly(
      Coordinator::Write::Events::CandidateCreatedV1,
      Coordinator::Write::Events::CandidateAssignedToAttemptV1,
      Coordinator::Write::Events::CandidateAssignedToRepositoryV1,
      Coordinator::Write::Events::CandidateTargetBranchSelectedV1,
      Coordinator::Write::Events::CandidateCommitRangeDeclaredV1,
      Coordinator::Write::Events::CandidateCheckpointKindSelectedV1,
      Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1,
      Coordinator::Write::Events::CandidateChangeManifestCapturedV2,
      Coordinator::Write::Events::CandidateSubmittedV3
    )
    expect(candidate_facts.map(&:target_stream).uniq).to contain_exactly(submitted_fact.target_stream)
  end

  it "rebinds post-remodel Candidate event references through persisted target plans" do
    seed_candidate_relationships
    candidate_events = persist_candidate_history
    submitted = candidate_events.fetch(:submitted)
    upper_position = submitted.global_position
    planned = planning_dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: submitted
    )
    expect(planned).to be_success

    selection = persist_payload(
      stream("DevelopmentExecution", "WorkItem", work_item_id),
      Coordinator::Write::Events::WorkItemCandidateSelectedV2.new(
        work_item_id:,
        change_set_id:,
        attempt_id:,
        candidate_id:,
        candidate_event: event_reference(submitted)
      )
    )

    fact = transform(selection, upper_position: selection.global_position).value!.sole
    target_submission = planned.value!.sole.target_event

    expect(fact.event.candidate_id).to eq(target_submission.stream_id)
    expect(fact.event.candidate_event).to eq(target_submission)
    expect(fact.event.candidate_event.event_id).not_to eq(submitted.id)
    expect(fact.event.candidate_event.stream_id).not_to eq(candidate_id)
  end

  it "targets the consumer WorkItem and rebinds dependency evidence emitted on a ChangeSet stream" do
    producer_id = "source-producer"
    consumer_id = "source-consumer"
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", producer_id), type: "WorkItemCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", consumer_id), type: "WorkItemCreated")
    completion = persist_payload(
      stream("DevelopmentExecution", "WorkItem", producer_id),
      Coordinator::Write::Events::WorkItemCompletedV2.new(work_item_id: producer_id)
    )
    planned = planning_dispatcher.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: completion.global_position,
      source_event: completion
    )
    expect(planned).to be_success

    satisfaction = persist_payload(
      stream("DevelopmentPlanning", "ChangeSet", change_set_id),
      Coordinator::Write::Events::WorkItemDependencySatisfiedV2.new(
        dependency_id: SecureRandom.uuid_v7,
        change_set_id:,
        producer_work_item_id: producer_id,
        consumer_work_item_id: consumer_id,
        dependency_kind: "requires_completion",
        required_output: nil,
        source: event_reference(completion)
      )
    )

    fact = transform(satisfaction, upper_position: satisfaction.global_position).value!.sole

    expect(fact.target_stream).to have_attributes(
      context: "DevelopmentExecution",
      stream_name: "WorkItem",
      stream_id: fact.event.consumer_work_item_id
    )
    expect(fact.event.consumer_work_item_id).not_to eq(consumer_id)
    expect(fact.event.producer_work_item_id).not_to eq(producer_id)
    expect(fact.event.source).to eq(planned.value!.sole.target_event)
  end

  def seed_execution_relationships
    persist_raw(stream("DevelopmentPlanning", "Repository", repository_id), type: "RepositoryRegistered")
    persist_raw(stream("DevelopmentPlanning", "ChangeSet", change_set_id), type: "ChangeSetCreated")
    persist_raw(stream("DevelopmentExecution", "WorkItem", work_item_id), type: "WorkItemCreated")
  end

  def seed_candidate_relationships
    seed_execution_relationships
    persist_payload(
      stream("DevelopmentExecution", "Attempt", attempt_id),
      Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id:)
    )
    persist_payload(
      stream("DevelopmentCoordination", "WorkIntentionSet", intention_set_id),
      Coordinator::Write::Events::WorkIntentionSetCreatedV1.new(
        set_id: intention_set_id,
        attempt_id:,
        work_item_id:,
        change_set_id:,
        repository_id:
      )
    )
  end

  def persist_candidate_history
    candidate_stream = stream("DevelopmentIntegration", "Candidate", candidate_id)
    payloads = {
      created: Coordinator::Write::Events::CandidateCreatedV1.new(candidate_id:),
      attempt: Coordinator::Write::Events::CandidateAssignedToAttemptV1.new(
        candidate_id:,
        attempt_id:,
        work_item_id:,
        change_set_id:
      ),
      repository: Coordinator::Write::Events::CandidateAssignedToRepositoryV1.new(
        candidate_id:,
        repository_id:
      ),
      branch: Coordinator::Write::Events::CandidateTargetBranchSelectedV1.new(
        candidate_id:,
        target_branch: "main"
      ),
      range: Coordinator::Write::Events::CandidateCommitRangeDeclaredV1.new(
        candidate_id:,
        object_format: "sha1",
        base_commit_oid: "a" * 40,
        head_commit_oid: "b" * 40
      ),
      checkpoint: Coordinator::Write::Events::CandidateCheckpointKindSelectedV1.new(
        candidate_id:,
        checkpoint_kind: "final"
      ),
      intention_set: Coordinator::Write::Events::CandidateWorkIntentionSetAssignedV1.new(
        candidate_id:,
        intention_set_id:
      ),
      manifest: Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
        candidate_id:,
        evidence_revision: 1,
        files: [
          Coordinator::Write::Candidates::ManifestFileV1.new(
            status: "modified",
            old_path: "README.md",
            new_path: "README.md",
            old_blob_oid: "1" * 40,
            new_blob_oid: "2" * 40,
            old_mode: "100644",
            new_mode: "100644"
          )
        ]
      ),
      submitted: Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:)
    }
    payloads.transform_values do |payload|
      metadata = if payload.is_a?(Coordinator::Write::Events::CandidateChangeManifestCapturedV2)
        {
          "policy_version" => "candidate-manifest/v2",
          "collector" => { "kind" => "agent", "id" => "codex", "collector_version" => "1" },
          "manifest_digest" => "sha256:#{'c' * 64}"
        }
      else
        {}
      end
      persist_payload(candidate_stream, payload, metadata:)
    end
  end

  def transform(source_event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event:
    )
  end

  def persist_payload(target_stream, payload, metadata: {})
    persist_raw(
      target_stream,
      type: payload.class.event_type,
      data: payload.to_h,
      schema_version: payload.class.schema_version,
      metadata:
    )
  end

  def persist_raw(target_stream, type:, data: {}, schema_version: 1, metadata: {})
    event_store.append(
      target_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type:,
          data:,
          metadata: {
            "schema_version" => schema_version,
            "command_id" => SecureRandom.uuid_v7,
            "actor_kind" => "agent",
            "actor_id" => "codex",
            "recorded_by" => "coordinator"
          }.merge(metadata),
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
end
