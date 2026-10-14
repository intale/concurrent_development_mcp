# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::CheckpointStatistics, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:loader) { Coordinator::Write::ProjectionStatistics::CheckpointsLoader.new(event_store:) }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "system", id: "checkpoint-process-spec") }
  let(:count) { Coordinator::Write::Operations::ExecuteCountCandidateCheckpoint.new(event_store:) }
  subject(:manager) { described_class.new(event_store:) }

  it "uses stable process decisions and immediate parents while counting the source only once" do
    source = arrange_sources(1).first
    manager.call(source)
    statistics_id = canonical_statistics
    before = history(statistics_id).map(&:id)
    manager.call(source)
    expect(history(statistics_id).map(&:id)).to eq(before)
    expect(loader.state(statistics_id).checkpoints_number).to eq(1)

    allocation = planned_step(source, "ensure", source.stream.stream_id)
    counted = planned_step(source, "count", statistics_id)
    facts = history(statistics_id)
    expect(facts.first(2).map(&:causation_id)).to eq([ allocation.id, allocation.id ])
    expect(facts.last(2).map(&:causation_id)).to eq([ counted.id, counted.id ])
    expect([ allocation, counted, *facts ].map(&:correlation_id).uniq).to eq([ source.correlation_id ])
    expect(facts.last.data.fetch("candidate_id")).to eq(source.stream.stream_id)
    definition = Coordinator::Processes::Subscriptions::CheckpointStatistics::DEFINITION
    expect(definition).to have_attributes(set_name: "coordinator-process-managers-v1",
      subscription_name: "checkpoint-statistics-v1", event_types: [ "CandidateSubmitted" ])
  end

  it "records failed dispatch rather than successful counting and repairs on later authorized redelivery" do
    sources = arrange_sources(4)
    source = sources.shift
    statistics_id = Coordinator::Write::Operations::ExecuteEnsureChangeSetRepositoryCheckpointStatistics.new(event_store:)
      .call_command(Coordinator::Write::Commands::EnsureChangeSetRepositoryCheckpointStatistics.new(
        command_id: SecureRandom.uuid_v7, actor:, statistics_id: SecureRandom.uuid_v7,
        change_set_id: "CS-LSE", repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID)).value!
    conflicts = 0
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.method_id == :append &&
                    frame.defined_class == Coordinator::Write::EventStore && sources.any?
      next unless frame.binding.local_variable_get(:events).any? { _1.type == "CandidateCheckpointCounted" }

      other = sources.shift
      conflicts += 1
      expect(count.call_command(count_command(statistics_id, other), caused_by: other)).to be_success
    end
    trace.enable { manager.call(source) }

    expect(conflicts).to eq(3)
    expect(loader.counted?(statistics_id, source.stream.stream_id)).to be(false)
    expect(loader.state(statistics_id).checkpoints_number).to eq(3)
    step = planned_step(source, "count", statistics_id)
    failure = event_store.read(streams.process_step(step.stream.stream_id),
      Coordinator::Write::EventReadCriteria.new(event_types: [ "ProcessStepDispatchFailed" ],
        maximum_count: 1, direction: :asc)).sole
    expect(failure.data).to include("code" => "concurrency_conflict", "retryable" => true)
    expect(failure.causation_id).to eq(step.id)
    expect(failure.correlation_id).to eq(source.correlation_id)

    manager.call(source)
    expect(loader.counted?(statistics_id, source.stream.stream_id)).to be(true)
    expect(loader.state(statistics_id).checkpoints_number).to eq(4)
    before = history(statistics_id).map(&:id)
    manager.call(source)
    expect(history(statistics_id).map(&:id)).to eq(before)
  ensure
    trace&.disable
  end

  def arrange_sources(number)
    WorkIntentionOperationScenario.start_attempts(event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    reservation = WorkIntentionOperationScenario.declare(event_store:,
      paths: [ { kind: "file", path: "lib/checkpoint.rb", base_blob_oid: "c" * 40 } ])
    number.times.map do |index|
      result = Coordinator::Write::Operations::ExecuteSubmitCandidate.new(event_store:).call(
        command_id: SecureRandom.uuid_v7, actor: { kind: "agent", id: "agent-a" },
        candidate_id: "CAN-PROCESS-#{index}", change_set_id: "CS-LSE", work_item_id: "W-LSE-A", attempt_id: "A-LSE-A",
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, target_branch: "main",
        base_commit_oid: "a" * 40, head_commit_oid: index.to_s(16).rjust(40, "d"), checkpoint_kind: "intermediate",
        intention_set_id: reservation.receipt.intention_set_id,
        intentions: WorkIntentionOperationScenario.work_intention_inputs(reservation.receipt),
        change_manifest: { collector_version: "git-evidence-v1", files: [
          { status: "modified", old_path: "lib/checkpoint.rb", new_path: "lib/checkpoint.rb",
            old_blob_oid: "c" * 40, new_blob_oid: "d" * 40, old_mode: "100644", new_mode: "100644" }
        ] })
      expect(result).to be_success
      emitted = result.value!.emitted_events.find { _1.type == "CandidateSubmitted" }
      event_store.read_at(streams.candidate(emitted.stream_id), emitted.stream_revision)
    end
  end

  def canonical_statistics
    Coordinator::Write::NaturalKeys::Registry.new(event_store:).find(
      selector: loader.selector(change_set_id: "CS-LSE", repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID),
      identity_from: ->(event) { event.data.fetch("statistics_id") }).value!.identity
  end

  def count_command(statistics_id, source)
    Coordinator::Write::Commands::CountCandidateCheckpoint.new(command_id: SecureRandom.uuid_v7, actor:, statistics_id:,
      source_event: Coordinator::Write::EventReference.new(event_id: source.id, type: source.type,
        stream_context: source.stream.context, stream_name: source.stream.stream_name,
        stream_id: source.stream.stream_id, stream_revision: source.stream_revision))
  end

  def planned_step(source, step_name, subject_id)
    marker = Coordinator::Shared::Markers::CodecV2.new.call(purpose: "process-step", components: [
      { dimension: "process-name", value: "checkpoint-statistics" },
      { dimension: "source-event-id", value: source.id }, { dimension: "step-name", value: step_name },
      { dimension: "subject-kind", value: "checkpoint-statistics" }, { dimension: "subject-id", value: subject_id }
    ]).value!.marker
    event_store.read_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
      stream_context: "CoordinatorControl", stream_name: "ProcessStep", event_types: [ "ProcessStepPlanned" ],
      markers: [ marker ], maximum_count: 1, direction: :asc)).sole
  end

  def history(statistics_id)
    event_store.read(streams.checkpoint_statistics(statistics_id), Coordinator::Write::EventReadCriteria.new(
      event_types: Coordinator::Write::EventQueries::CHECKPOINT_STATISTICS_CONTROL.event_types,
      maximum_count: 32, direction: :asc))
  end
end
