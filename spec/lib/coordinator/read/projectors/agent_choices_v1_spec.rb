# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoicesV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  it "projects recorded and accepted evidence idempotently without withholding either stage" do
    scenario = AgentChoiceScenario.record_no_policy_choice(prefix: "choice-project")
    recorded, accepted = scenario.fetch(:events)

    projector.call(recorded)
    projector.call(recorded)

    available = repository.fetch("CHO-choice-project")
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
      markers: include("choice:CHO-choice-project", "repository:billing"),
      metadata: include("command_id" => "cmd-choice-project-choice", "schema_version" => 1),
      causation_id: recorded.causation_id,
      correlation_id: recorded.correlation_id
    )

    projector.call(accepted)
    projector.call(accepted)

    projected = repository.fetch("CHO-choice-project")
    expect(projected).to have_attributes(
      observation_status: "accepted",
      context_digest: scenario.fetch(:decision_context).digest
    )
    expect(projected.assessment).to have_attributes(
      basis: "no_policy",
      based_on_decisions: [],
      warnings: []
    )
    expect(projected.accepted.to_h).to include(
      event: include(event_id: accepted.id, type: "AgentChoiceAccepted", stream_revision: 1),
      actor: include(kind: "agent", id: "agent-a", authenticated: false),
      markers: include("choice:CHO-choice-project", "attempt:A-choice-project"),
      metadata: include("command_id" => "cmd-choice-project-choice", "schema_version" => 1),
      causation_id: accepted.causation_id,
      correlation_id: accepted.correlation_id
    )
    expect(Coordinator::Read::AgentChoice.count).to eq(1)
    expect(processed_events.count).to eq(2)
  end

  it "rolls back the idempotency claim when accepted evidence arrives before recorded evidence" do
    recorded, accepted = AgentChoiceScenario.record_no_policy_choice(
      prefix: "choice-order"
    ).fetch(:events)

    expect { projector.call(accepted) }.to raise_error(
      Coordinator::Read::ProjectionStateError,
      "AgentChoiceRecorded must be projected before AgentChoiceAccepted"
    )
    expect(processed_events).to be_empty

    projector.call(recorded)
    projector.call(accepted)
    expect(repository.fetch("CHO-choice-order")).to have_attributes(
      observation_status: "accepted"
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
