# frozen_string_literal: true

RSpec.describe Coordinator::Processes::BuildProgress::SourceBuilder, :event_store do
  subject(:source_builder) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:stream_factory) { Coordinator::Write::StreamFactory.new }
  let(:event_factory) { Coordinator::Write::EventFactory.new }

  it "resolves a granular completion from its Candidate selection without an aggregate membership fact" do
    change_set_id = SecureRandom.uuid_v7
    work_item_id = SecureRandom.uuid_v7
    attempt_id = SecureRandom.uuid_v7
    candidate_id = SecureRandom.uuid_v7
    correlation_id = SecureRandom.uuid_v7
    stream = stream_factory.work_item(work_item_id)
    metadata = Coordinator::Write::EventMetadata.new(
      command_id: "source-builder-granular-completion",
      actor_kind: "agent",
      actor_id: "codex",
      recorded_by: "coordinator",
      policy_version: nil
    )
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: candidate_id,
      stream_revision: 8
    )
    events = [
      Coordinator::Write::Events::WorkItemCandidateSelectedV2.new(
        work_item_id:,
        change_set_id:,
        attempt_id:,
        candidate_id:,
        candidate_event:
      ),
      Coordinator::Write::Events::WorkItemCompletedV2.new(work_item_id:)
    ].map do |event|
      event_factory.build!(
        event:,
        event_id: SecureRandom.uuid_v7,
        metadata:,
        markers: [ "work-item:#{work_item_id}" ],
        correlation_id:
      )
    end
    source_event = event_store.append(stream, events).last

    expect(source_builder.call(source_event)).to have_attributes(
      payload: an_instance_of(Coordinator::Write::Events::WorkItemCompletedV2),
      change_set_id:
    )
  end
end
