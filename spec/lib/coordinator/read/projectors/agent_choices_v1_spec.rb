# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoicesV1, :read_model do
  subject(:projector) { described_class.new }

  let(:choice_id) { "CHO-choice-project" }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000001" }
  let(:stream) { Coordinator::Write::StreamFactory.new.agent_choice(choice_id) }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects recorded and accepted evidence idempotently without withholding either stage" do
    recorded, accepted = choice_events

    projector.call(recorded)
    projector.call(recorded)

    available = repository.fetch(choice_id)
    expect(available).to have_attributes(
      choice_type: "testing.framework",
      observation_status: "recorded",
      selected: have_attributes(option_id: "rspec"),
      assessment: nil,
      accepted: nil
    )
    expect(available.recorded.to_h).to include(
      event: include(event_id: recorded.id, type: "AgentChoiceRecorded", stream_revision: 0),
      actor: include(kind: "agent", id: "agent-a", authenticated: false),
      markers: include("choice:#{choice_id}", "repository:#{repository_id}"),
      causation_id: recorded.causation_id,
      correlation_id: recorded.correlation_id
    )

    projector.call(accepted)
    projector.call(accepted)

    projected = repository.fetch(choice_id)
    expect(projected).to have_attributes(
      observation_status: "accepted",
      context_digest: decision_context.digest,
      assessment: have_attributes(basis: "no_policy", based_on_decisions: [], warnings: [])
    )
    expect(projected.accepted.to_h).to include(
      event: include(event_id: accepted.id, type: "AgentChoiceAccepted", stream_revision: 1),
      actor: include(kind: "agent", id: "agent-a", authenticated: false),
      markers: include("choice:#{choice_id}", "attempt:A-choice-project"),
      causation_id: accepted.causation_id,
      correlation_id: accepted.correlation_id
    )
    expect(Coordinator::Read::AgentChoice.count).to eq(1)
    expect(processed_events.count).to eq(2)
  end

  it "rolls back the idempotency claim when accepted evidence arrives first" do
    recorded, accepted = choice_events

    expect { projector.call(accepted) }.to raise_error(
      Coordinator::Read::ProjectionStateError,
      "AgentChoiceRecorded must be projected before AgentChoiceAccepted"
    )
    expect(processed_events).to be_empty

    projector.call(recorded)
    projector.call(accepted)
    expect(repository.fetch(choice_id)).to have_attributes(observation_status: "accepted")
  end

  def choice_events
    recorded = ProjectionEventFactory.build(
      payload: recorded_payload,
      stream:,
      stream_revision: 0,
      global_position: 100,
      command_id: "cmd-choice-project-choice",
      actor_id: "agent-a",
      policy_version: "testing-framework-resolution/v1",
      correlation_id:,
      markers: [ "choice:#{choice_id}", "repository:#{repository_id}" ]
    )
    accepted_payload = Coordinator::Write::Events::AgentChoiceAcceptedV1.new(
      choice_id:,
      recorded_event: event_reference(recorded),
      context_digest: decision_context.digest,
      assessment: Coordinator::Write::AgentChoices::ChoiceAssessmentV1.new(
        basis: "no_policy",
        based_on_decisions: [],
        warnings: []
      ),
      accepted_at: "2026-08-30T12:01:00.000000Z"
    )
    accepted = ProjectionEventFactory.build(
      payload: accepted_payload,
      stream:,
      stream_revision: 1,
      global_position: 200,
      command_id: "cmd-choice-project-choice",
      actor_id: "agent-a",
      policy_version: "testing-framework-resolution/v1",
      correlation_id:,
      causation_id: recorded.id,
      markers: [ "choice:#{choice_id}", "attempt:A-choice-project" ]
    )
    [ recorded, accepted ]
  end

  def recorded_payload
    Coordinator::Write::Events::AgentChoiceRecordedV1.new(
      choice_id:,
      choice_type: "testing.framework",
      selected: Coordinator::Write::AgentChoices::ChoiceOptionV1.new(
        option_id: "rspec",
        summary: "Use RSpec"
      ),
      alternatives: [],
      reason_summary: "RSpec is already established in the project.",
      context: query_context,
      decision_context:,
      recorded_at: "2026-08-30T12:00:00.000000Z"
    )
  end

  def query_context
    @query_context ||= Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id:,
      change_set_id: "CS-choice-project",
      work_item_id: "W-choice-project",
      attempt_id: "A-choice-project",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/example_spec.rb" ],
      environment: "test",
      agent_role: "developer"
    )
  end

  def decision_context
    @decision_context ||= begin
      observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(query_context).map do |partition|
        Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
          partition:,
          partition_revision: nil,
          event: nil,
          active_decisions: []
        )
      end
      resolution = Coordinator::Write::DecisionContexts::ResultV1.new(
        effective_decision: nil,
        shadowed_decisions: [],
        conflict: nil,
        unsupported_dimensions: [],
        unsupported_decisions: [],
        unresolved_decisions: []
      )
      Coordinator::Write::DecisionContexts::Builder.new.call(
        context: query_context,
        observations:,
        resolution:,
        resolved_at: "2026-08-30T12:00:00.000000Z"
      )
    end
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

  def repository
    @repository ||= Coordinator::Read::Repositories::AgentChoices.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "agent_choices",
      projection_version: 1
    )
  end
end
