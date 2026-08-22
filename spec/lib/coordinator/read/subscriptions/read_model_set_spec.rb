# frozen_string_literal: true

RSpec.describe Coordinator::Read::Subscriptions::ReadModelSet, :event_store, :read_model do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:context_registration) do
    Coordinator::Read::Subscriptions::CoordContext.new(
      handler: Coordinator::Read::Projectors::CoordContextV1.new,
      pull_interval: 0.2
    )
  end
  let(:receipt_registration) do
    Coordinator::Read::Subscriptions::CommandReceipts.new(
      handler: Coordinator::Read::Projectors::CommandReceiptsV1.new,
      pull_interval: 0.2
    )
  end
  let(:utterance_registration) do
    Coordinator::Read::Subscriptions::UserUtterances.new(
      handler: Coordinator::Read::Projectors::UserUtterancesV1.new,
      pull_interval: 0.2
    )
  end
  let(:interpretation_registration) do
    Coordinator::Read::Subscriptions::DecisionInterpretations.new(
      handler: Coordinator::Read::Projectors::DecisionInterpretationsV1.new,
      pull_interval: 0.2
    )
  end

  it "stacks four unique durable subscriptions on one read-model manager" do
    subscription_set = build_set

    expect(subscription_set.subscription_names).to eq(
      [
        "command-receipts-v1",
        "coord-context-v1",
        "decision-interpretations-v1",
        "user-utterances-v1"
      ]
    )
    expect(context_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "coord-context-v1"
    )
    expect(receipt_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "command-receipts-v1"
    )
    expect(utterance_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "user-utterances-v1"
    )
    expect(interpretation_registration.definition.identity.to_h).to eq(
      set_name: "coordinator-read-models-v1",
      subscription_name: "decision-interpretations-v1"
    )
  end

  it "runs all projections through a real filtered pg_eventstore subscription set" do
    subscription_set = build_set

    begin
      subscription_set.start
      Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
        command_id: "cmd-subscription-100",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-SUB-100",
        goal: "Exercise both read models",
        acceptance_criteria: [ "Both subscriptions advance" ]
      ).value!
      Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
        command_id: "cmd-subscription-guidance",
        actor: { kind: "agent", id: "host-1" },
        message_id: "M-subscription",
        conversation_id: "C-subscription",
        source: "mcp_client",
        text: "Project attributed guidance evidence.",
        anchors: {
          repository_ids: [],
          change_set_id: nil,
          work_item_id: nil,
          attempt_id: nil
        }
      ).value!
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation.new(event_store:).call(
        InterpretationInput.build(
          command_id: "cmd-subscription-interpretation",
          interpretation_id: "I-subscription",
          source_message_id: "M-subscription",
          source_span: { start_character: 19, end_character: 27, text: "guidance" }
        )
      ).value!

      wait_for(subscription_set, "coord-context-v1", minimum: 2)
      wait_for(subscription_set, "command-receipts-v1", minimum: 3)
      wait_for(subscription_set, "user-utterances-v1", minimum: 1)
      wait_for(subscription_set, "decision-interpretations-v1", minimum: 1)

      expect(Coordinator::Read::CoordContext.find("CS-SUB-100").document).to include(
        "schema" => "coord-context/v1"
      )
      expect(Coordinator::Read::CommandReceipt.find("cmd-subscription-100").tool_name).to eq(
        "change_set_create"
      )
      expect(Coordinator::Read::UserUtterance.find("M-subscription").policy_status).to eq(
        "evidence_only"
      )
      expect(Coordinator::Read::DecisionInterpretation.find("I-subscription")).to have_attributes(
        message_id: "M-subscription",
        policy_status: "proposal_only"
      )
    ensure
      subscription_set.stop
    end
  end

  def build_set
    manager = PgEventstore.subscriptions_manager(
      subscription_set: described_class::SET_NAME
    )
    described_class.new(
      manager:,
      registrations: [
        context_registration,
        receipt_registration,
        utterance_registration,
        interpretation_registration
      ]
    )
  end

  def wait_for(subscription_set, subscription_name, minimum:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until subscription_set.processed_event_count(subscription_name) >= minimum
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "#{subscription_name} did not process #{minimum} events within 10 seconds"
      end

      sleep 0.05
    end
  end
end
