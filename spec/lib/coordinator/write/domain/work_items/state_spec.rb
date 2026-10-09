# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::WorkItems::State do
  let(:definition) do
    [
      Coordinator::Write::Events::WorkItemCreatedV2.new(work_item_id: "W-200"),
      Coordinator::Write::Events::WorkItemAddedToChangeSetV2.new(
        work_item_id: "W-200", change_set_id: "CS-100"
      ),
      Coordinator::Write::Events::WorkItemAssignedToRepositoryV1.new(
        work_item_id: "W-200", repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
      ),
      Coordinator::Write::Events::WorkItemGoalDefinedV1.new(
        work_item_id: "W-200", goal: "Implement capture validation"
      ),
      Coordinator::Write::Events::WorkItemAcceptanceCriteriaDefinedV1.new(
        work_item_id: "W-200", acceptance_criteria: [ "Reject duplicate ownership" ]
      ),
      Coordinator::Write::Events::WorkItemCompetitiveModeSelectedV1.new(
        work_item_id: "W-200", competitive_mode: false
      )
    ]
  end
  let(:made_ready) do
    Coordinator::Write::Events::WorkItemMadeReadyV2.new(
      change_set_id: "CS-100",
      work_item_id: "W-200",
      readiness_decision_id: SecureRandom.uuid_v7,
      reason: "change_set_activated"
    )
  end
  let(:acquired) do
    Coordinator::Write::Events::WorkItemAcquiredV2.new(
      change_set_id: "CS-100", work_item_id: "W-200", attempt_id: "A-300", agent_id: "agent-a"
    )
  end

  it "folds separate definition facts into the authoritative planned state" do
    state = described_class.reduce(definition)

    expect(state.to_h).to eq(
      work_item_id: "W-200",
      change_set_id: "CS-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement capture validation",
      acceptance_criteria: [ "Reject duplicate ownership" ],
      competitive_mode: false,
      status: "planned",
      active_attempt_id: nil,
      active_agent_id: nil,
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      produced_outputs: []
    )
    expect(state).to be_frozen
  end

  it "applies WorkItemMadeReady to the authoritative lifecycle state" do
    ready = described_class.reduce([ *definition, made_ready ])

    expect(ready).to have_attributes(
      status: "ready", work_item_id: "W-200", repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
    )
  end

  it "applies WorkItemAcquired as authoritative active ownership" do
    state = described_class.reduce([ *definition, made_ready, acquired ])

    expect(state).to have_attributes(status: "active", active_attempt_id: "A-300", active_agent_id: "agent-a")
  end

  it "retains separate Candidate selection and output facts after lean completion" do
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-400",
      stream_revision: 0
    )
    output = Coordinator::Write::WorkItemOutputV1.new(kind: "artifact", key: "billing-gem")
    state = described_class.reduce([
      *definition, made_ready, acquired,
      Coordinator::Write::Events::WorkItemCandidateSelectedV2.new(
        change_set_id: "CS-100", work_item_id: "W-200", attempt_id: "A-300",
        candidate_id: "CAN-400", candidate_event:
      ),
      Coordinator::Write::Events::WorkItemOutputRecordedV1.new(
        work_item_id: "W-200", output_kind: output.kind, output_key: output.key
      ),
      Coordinator::Write::Events::WorkItemCompletedV2.new(work_item_id: "W-200")
    ])

    expect(state).to have_attributes(
      status: "completed", selected_candidate_id: "CAN-400",
      selected_candidate_event: candidate_event, produced_outputs: [ output ]
    )
  end
end
