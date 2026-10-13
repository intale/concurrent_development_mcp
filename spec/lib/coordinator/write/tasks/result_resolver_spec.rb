# frozen_string_literal: true

RSpec.describe Coordinator::Write::Tasks::ResultResolver, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:submit) { Coordinator::Write::Operations::SubmitCoordinationTask.new(event_store:) }
  let(:executor) { Coordinator::Processes::ProcessManagers::CoordinationTaskExecutor.new(event_store:) }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "agent", id: "receipt-agent") }

  it "reconstructs a successful terminal receipt without running any projector" do
    task = submit.call(change_set("create-once")).value!
    execute(task)
    state = Coordinator::Write::Tasks::Loader.new(event_store:).call(task.task_id).state
    result = described_class.new(event_store:).call(state)
    expect(result).to be_a(Coordinator::Write::Tasks::SemanticResultV1::Success)
    expect(result.data.change_set_id).to eq("authoritative-receipt-CS")
    expect(result.completion).to have_attributes(scope: "command", outcome: "succeeded", effects: "committed", read_back_required: false)
    expect(described_class.new(event_store:).call(state)).to eq(result)
  end

  it "reconstructs a durable denial without read-side receipt state" do
    seed = submit.call(change_set("seed")).value!
    execute(seed)
    denied = submit.call(change_set("denied")).value!
    execute(denied)
    state = Coordinator::Write::Tasks::Loader.new(event_store:).call(denied.task_id).state
    result = described_class.new(event_store:).call(state)
    expect(result).to be_a(Coordinator::Write::Tasks::SemanticResultV1::DomainRejection)
    expect(result.error.code).to eq("change_set_already_exists")
    expect(result.completion).to have_attributes(outcome: "denied", effects: "none", read_back_required: false)
  end

  def change_set(request_id)
    Coordinator::Write::Commands::CreateChangeSet.new(command_id: request_id, actor:,
      change_set_id: "authoritative-receipt-CS", goal: "Authoritative terminal receipts",
      acceptance_criteria: [ "No projector is needed to recover the outcome" ])
  end

  def execute(task)
    event = event_store.read(streams.coordination_task(task.task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY).first
    executor.call(event)
  end
end
