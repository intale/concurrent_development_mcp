# frozen_string_literal: true

RSpec.describe Coordinator::Read::CoordContexts::SourceLoader, :event_store do
  subject(:loader) do
    described_class.new(
      event_store:,
      submission_loader: Coordinator::Read::Candidates::SubmissionLoader.new(event_store:)
    )
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:factory) { Coordinator::Write::EventFactory.new }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:metadata) do
    Coordinator::Write::EventMetadata.new(
      command_id: SecureRandom.uuid_v7,
      actor_kind: "agent",
      actor_id: "codex",
      recorded_by: "coordinator",
      policy_version: nil
    )
  end

  it "reconstructs cohesive target definitions and completion from bounded granular facts" do
    change_set_id = SecureRandom.uuid_v7
    work_item_id = SecureRandom.uuid_v7
    attempt_id = SecureRandom.uuid_v7
    repository_id = SecureRandom.uuid_v7
    candidate_id = SecureRandom.uuid_v7
    output_key = SecureRandom.uuid_v7
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: candidate_id,
      stream_revision: 9
    )

    change_set_events = append(
      streams.change_set(change_set_id),
      Coordinator::Write::Events::ChangeSetCreatedV2.new(change_set_id:),
      Coordinator::Write::Events::ChangeSetGoalDefinedV1.new(
        change_set_id:,
        goal: "Rebuild the read side"
      ),
      Coordinator::Write::Events::ChangeSetAcceptanceCriteriaDefinedV2.new(
        change_set_id:,
        acceptance_criteria: [ "The projection is deterministic" ]
      )
    )
    work_item_events = append(
      streams.work_item(work_item_id),
      Coordinator::Write::Events::WorkItemCreatedV2.new(work_item_id:),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(work_item_id:, change_set_id:),
      Coordinator::Write::Events::WorkItemAssignedToRepositoryV1.new(work_item_id:, repository_id:),
      Coordinator::Write::Events::WorkItemGoalDefinedV1.new(
        work_item_id:,
        goal: "Project granular facts"
      ),
      Coordinator::Write::Events::WorkItemAcceptanceCriteriaDefinedV1.new(
        work_item_id:,
        acceptance_criteria: [ "A cohesive view is available" ]
      ),
      Coordinator::Write::Events::WorkItemCompetitiveModeSelectedV1.new(
        work_item_id:,
        competitive_mode: false
      )
    )
    attempt_events = append(
      streams.attempt(attempt_id),
      Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id:),
      Coordinator::Write::Events::AttemptAssignedToWorkItemV1.new(
        attempt_id:,
        change_set_id:,
        work_item_id:
      ),
      Coordinator::Write::Events::AttemptAssignedToAgentV1.new(attempt_id:, agent_id: "codex"),
      Coordinator::Write::Events::AttemptBaseSnapshotRecordedV1.new(
        attempt_id:,
        repository_id:,
        object_format: "sha1",
        commit_oid: "a" * 40
      ),
      Coordinator::Write::Events::AttemptStartedV2.new(attempt_id:)
    )
    completion_events = append(
      streams.work_item(work_item_id),
      Coordinator::Write::Events::WorkItemCandidateSelectedV2.new(
        work_item_id:,
        change_set_id:,
        attempt_id:,
        candidate_id:,
        candidate_event:
      ),
      Coordinator::Write::Events::WorkItemOutputRecordedV1.new(
        work_item_id:,
        output_kind: "artifact",
        output_key:
      ),
      Coordinator::Write::Events::WorkItemCompletedV2.new(work_item_id:)
    )

    change_set = load(change_set_events.last)
    work_item = load(work_item_events.last)
    attempt = load(attempt_events.last)
    completion = load(completion_events.last)

    expect(loader.call(change_set_events.last, change_set)).to have_attributes(
      change_set_id:,
      goal: "Rebuild the read side",
      acceptance_criteria: [ "The projection is deterministic" ],
      created_at: timestamp(change_set_events.first)
    )
    expect(loader.call(work_item_events.last, work_item)).to have_attributes(
      work_item_id:,
      change_set_id:,
      repository_id:,
      goal: "Project granular facts",
      acceptance_criteria: [ "A cohesive view is available" ],
      competitive_mode: false,
      created_at: timestamp(work_item_events.first)
    )
    expect(loader.call(attempt_events.last, attempt)).to have_attributes(
      attempt_id:,
      change_set_id:,
      work_item_id:,
      agent_id: "codex",
      authorized_at: timestamp(attempt_events.first),
      started_at: timestamp(attempt_events.last)
    )
    expect(loader.call(completion_events.last, completion)).to have_attributes(
      work_item_id:,
      change_set_id:,
      attempt_id:,
      candidate_id:,
      candidate_event:,
      produced_outputs: [ Coordinator::Write::WorkItemOutputV1.new(kind: "artifact", key: output_key) ],
      completed_at: timestamp(completion_events.last)
    )
  end

  private

  def append(stream, *facts)
    events = facts.map do |fact|
      factory.build!(
        event: fact,
        event_id: SecureRandom.uuid_v7,
        metadata:,
        markers: [],
        correlation_id:
      )
    end
    event_store.append(stream, events)
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def timestamp(event)
    event.created_at.utc.iso8601(6)
  end
end
