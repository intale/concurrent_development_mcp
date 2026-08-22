# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExpectedRevisionRetry, :event_store do
  include Dry::Monads[:result]

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  let(:event_factory) { Coordinator::Write::EventFactory.new(registry: schemas) }
  let(:id_generator) { Coordinator::Shared::IdGenerator.new }
  let(:loader) do
    Coordinator::Write::Tasks::Loader.new(
      event_store:,
      stream_factory: streams,
      schema_registry: schemas
    )
  end
  let(:transition) do
    Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(
      event_store:,
      loader:,
      stream_factory: streams,
      event_factory:
    )
  end
  let(:submit) do
    Coordinator::Write::Operations::SubmitCoordinationTask.new(
      event_store:,
      stream_factory: streams,
      event_factory:
    )
  end
  let(:cancel) { Coordinator::Write::Operations::CancelCoordinationTask.new(transition:) }
  let(:reported_task_id) { "01919191-9191-7191-8191-919191919191" }

  it "retries after a real wrong-revision race and returns the later result" do
    attempts = 0

    result = described_class.new.call(task_id: reported_task_id) do
      attempts += 1
      force_real_wrong_revision(attempts) if attempts == 1
      Success(:retried)
    end

    expect(result).to be_success
    expect(result.value!).to eq(:retried)
    expect(attempts).to eq(2)
  end

  it "returns an actionable failure after three real wrong-revision races" do
    attempts = 0

    result = described_class.new.call(task_id: reported_task_id) do
      attempts += 1
      force_real_wrong_revision(attempts)
    end

    expect(result).to be_failure
    expect(result.failure).to eq(
      Coordinator::Write::Tasks::LifecycleError.new(
        code: :concurrency_conflict,
        message: "Task changed concurrently; the request may succeed if retried",
        task_id: reported_task_id
      )
    )
    expect(attempts).to eq(3)
  end

  def force_real_wrong_revision(sequence)
    task_state = submit.call(target_command(sequence)).value!
    task_id = task_state.task_id
    snapshot = loader.call(task_id)
    command = Coordinator::Write::Commands::StartCoordinationTask.new(
      task_id:,
      started_at: Coordinator::Shared::SystemClock.new.now
    )
    planned_event = Coordinator::Write::Domain::CoordinationTasks::Start.new.call(
      state: snapshot.state,
      command:
    ).value!

    cancel.call(task_id:).value!

    event_store.append(
      streams.coordination_task(task_id),
      [
        event_factory.build!(
          event: planned_event,
          event_id: id_generator.uuid_v7,
          metadata: Coordinator::Write::EventMetadata.new(
            command_id: "task:#{task_id}:forced-race",
            actor_kind: "system",
            actor_id: "coordinator",
            recorded_by: "coordinator",
            policy_version: "coordination-task/v1"
          ),
          markers: [ "task:#{task_id}" ]
        )
      ],
      expected_revision: snapshot.latest_revision
    )
  end

  def target_command(sequence)
    suffix = id_generator.uuid_v7

    Coordinator::Write::Commands::CreateChangeSet.new(
      command_id: "retry-#{suffix}",
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "coordinator"),
      change_set_id: "CS-retry-#{sequence}-#{suffix}",
      goal: "Prove bounded expected-revision retry",
      acceptance_criteria: [ "The real stale append is rejected" ]
    )
  end
end
