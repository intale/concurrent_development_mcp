# frozen_string_literal: true

RSpec.describe "Checkpoint statistics", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "system", id: "checkpoint-statistics-spec") }
  let(:loader) { Coordinator::Write::ProjectionStatistics::CheckpointsLoader.new(event_store:) }
  let(:ensure_statistics) { Coordinator::Write::Operations::ExecuteEnsureChangeSetRepositoryCheckpointStatistics.new(event_store:) }
  let(:count) { Coordinator::Write::Operations::ExecuteCountCandidateCheckpoint.new(event_store:) }

  it "allocates one canonical owner UUID without advancing the ChangeSet stream" do
    reservation = arrange
    parent_before = event_store.read_grouped(streams.change_set("CS-LSE"), Coordinator::Write::EventQueries::CHANGE_SET_EXISTENCE)
    commands = Array.new(2) { ensure_command }
    results = concurrently(commands) { ensure_statistics.call_command(_1) }

    expect(results).to all(be_success)
    expect(results.map(&:value!).uniq.length).to eq(1)
    statistics_id = results.first.value!
    facts = history(statistics_id)
    expect(facts.map(&:type)).to eq(%w[
      ChangeSetRepositoryCheckpointStatisticsAssigned ChangeSetRepositoryCheckpointNumberChanged
    ])
    expect(facts.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(facts.last.data).to include("checkpoints_number" => 0)
    expect(facts.first.markers).to include(loader.selector(
      change_set_id: "CS-LSE", repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID).marker)
    expect(event_store.read_grouped(streams.change_set("CS-LSE"),
      Coordinator::Write::EventQueries::CHANGE_SET_EXISTENCE).map(&:id)).to eq(parent_before.map(&:id))

    calls, queries = [], []
    trace = observations(calls, queries)
    replay = trace.enable { ensure_statistics.call_command(ensure_command) }
    expect(replay.value!).to eq(statistics_id)
    expect(calls).not_to include(:multiple, :append)
    expect(reservation.receipt.intentions.length).to eq(1)
  ensure
    trace&.disable
  end

  it "denies missing owners without assigning any statistics facts" do
    command = ensure_command
    result = ensure_statistics.call_command(command)

    expect(result.failure.code).to eq(:change_set_not_found)
    expect(history(command.statistics_id)).to be_empty
    arrange
    missing_repository = ensure_command(repository_id: SecureRandom.uuid_v7)
    result = ensure_statistics.call_command(missing_repository)
    expect(result.failure.code).to eq(:repository_not_registered)
    expect(history(missing_repository.statistics_id)).to be_empty
  end

  it "counts an accepted checkpoint with exact narrow source queries and native tracing" do
    source = submit(arrange, 1)
    statistics_id = ensure_statistics.call_command(ensure_command, caused_by: source).value!
    calls, queries = [], []
    trace = observations(calls, queries)
    result = trace.enable { count.call_command(count_command(statistics_id, source), caused_by: source) }

    expect(result).to be_success
    expect(calls.first).to eq(:read_grouped)
    expect(calls).not_to include(:multiple, :read_global_marked)
    expect(queries.map(&:event_types)).to eq([
      loader.class::CANDIDATE_TYPES, loader.class::ATTEMPT_TYPES, loader.class::WORK_ITEM_TYPES
    ])
    expect(queries.map(&:maximum_count)).to eq([ 3, 3, 3 ])
    facts = history(statistics_id).last(2)
    expect(facts.map(&:type)).to eq(%w[ChangeSetRepositoryCheckpointNumberChanged CandidateCheckpointCounted])
    expect(facts.first.data).to include("checkpoints_number" => 1)
    expect(facts.last.data).to eq("statistics_id" => statistics_id, "candidate_id" => source.stream.stream_id)
    expect(facts.map(&:causation_id)).to eq([ source.id, source.id ])
    expect(facts.map(&:correlation_id)).to eq([ source.correlation_id, source.correlation_id ])
  ensure
    trace&.disable
  end

  it "does not recount a Candidate even when a replay has a different command ID" do
    source = submit(arrange, 1)
    statistics_id = ensure_statistics.call_command(ensure_command).value!
    expect(count.call_command(count_command(statistics_id, source))).to be_success
    before = history(statistics_id).map(&:id)
    expect(count.call_command(count_command(statistics_id, source)).value!).to be_nil
    expect(history(statistics_id).map(&:id)).to eq(before)
    expect(loader.state(statistics_id).checkpoints_number).to eq(1)
  end

  it "converges independent Candidates under concurrent and reversed delivery" do
    reservation = arrange
    sources = [ submit(reservation, 1), submit(reservation, 2), submit(reservation, 3) ]
    statistics_id = ensure_statistics.call_command(ensure_command).value!
    results = concurrently(sources.first(2)) { count.call_command(count_command(statistics_id, _1)) }
    expect(results).to all(be_success)
    expect(count.call_command(count_command(statistics_id, sources.last))).to be_success
    before = history(statistics_id).map(&:id)
    sources.reverse_each { expect(count.call_command(count_command(statistics_id, _1)).value!).to be_nil }
    expect(history(statistics_id).map(&:id)).to eq(before)
    expect(loader.state(statistics_id).checkpoints_number).to eq(3)
    expect(history(statistics_id).select { _1.type == "CandidateCheckpointCounted" }
      .map { _1.data.fetch("candidate_id") }).to match_array(sources.map { _1.stream.stream_id })
  end

  it "keeps repository owners independent and rejects a Candidate from another owner" do
    source = submit(arrange, 1)
    first_id = ensure_statistics.call_command(ensure_command).value!
    repository_id = RepositoryScenario.register(event_store:, key: "statistics-other")
    second_id = ensure_statistics.call_command(ensure_command(repository_id:)).value!
    expect(second_id).not_to eq(first_id)
    before = history(second_id).map(&:id)
    rejected = count.call_command(count_command(second_id, source))
    expect(rejected.failure.code).to eq(:projection_statistics_source_mismatch)
    expect(history(second_id).map(&:id)).to eq(before)
    expect(count.call_command(count_command(first_id, source))).to be_success
    expect(loader.state(first_id).checkpoints_number).to eq(1)
    expect(loader.state(second_id).checkpoints_number).to eq(0)
  end

  it "rejects the wrong persisted source reference without marking a Candidate counted" do
    source = submit(arrange, 1)
    statistics_id = ensure_statistics.call_command(ensure_command).value!
    command = count_command(statistics_id, source)
    wrong_reference = Coordinator::Write::EventReference.new(
      command.source_event.to_h.merge(event_id: SecureRandom.uuid_v7))
    invalid = command.new(source_event: wrong_reference)
    before = history(statistics_id).map(&:id)
    result = count.call_command(invalid)
    expect(result.failure.code).to eq(:projection_statistics_source_mismatch)
    expect(history(statistics_id).map(&:id)).to eq(before)
    expect(loader.counted?(statistics_id, source.stream.stream_id)).to be(false)
  end

  it "returns a retryable failure after three real revision races with no attempted count committed" do
    reservation = arrange
    sources = 4.times.map { submit(reservation, _1 + 1) }
    source = sources.shift
    statistics_id = ensure_statistics.call_command(ensure_command).value!
    interferences = []
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.method_id == :append &&
                    frame.defined_class == Coordinator::Write::EventStore && sources.any?

      other = sources.shift
      interferences << count.call_command(count_command(statistics_id, other), caused_by: other)
    end
    result = trace.enable { count.call_command(count_command(statistics_id, source), caused_by: source) }

    expect(interferences.length).to eq(3)
    expect(interferences).to all(be_success)
    expect(result.failure).to have_attributes(code: :concurrency_conflict)
    expect(result.failure.message).to include("three attempts", "retried")
    expect(loader.counted?(statistics_id, source.stream.stream_id)).to be(false)
    expect(loader.state(statistics_id).checkpoints_number).to eq(3)
    expect(history(statistics_id).count { _1.type == "CandidateCheckpointCounted" }).to eq(3)
    expect(count.call_command(count_command(statistics_id, source))).to be_success
    expect(loader.state(statistics_id).checkpoints_number).to eq(4)
  ensure
    trace&.disable
  end

  it "requires exact immutable Candidate, Attempt and WorkItem associations before any counting effect" do
    arrange
    statistics_id = ensure_statistics.call_command(ensure_command).value!
    before = history(statistics_id).map(&:id)
    [ { attempt_id: "missing-attempt" }, { work_item_id: "missing-work-item" }, { change_set_id: "wrong-change-set" } ]
      .each_with_index do |mismatch, index|
        candidate_id = "CAN-WRONG-SCOPE-#{index}"
        assignment = { candidate_id:, attempt_id: "A-LSE-A", work_item_id: "W-LSE-A", change_set_id: "CS-LSE" }.merge(mismatch)
        payloads = [
          Coordinator::Write::Events::CandidateAssignedToAttemptV1.new(assignment),
          Coordinator::Write::Events::CandidateAssignedToRepositoryV1.new(
            candidate_id:, repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID),
          Coordinator::Write::Events::CandidateSubmittedV3.new(candidate_id:)
        ]
        # Concrete persisted-reference fixtures intentionally contain mismatched
        # associations; no collaborator replaces the real event-store boundary.
        physical = payloads.map do |event|
          Coordinator::Write::EventFactory.new.build!(event:, event_id: SecureRandom.uuid_v7, markers: [],
            metadata: Coordinator::Write::EventMetadata.new(command_id: SecureRandom.uuid_v7,
              actor_kind: actor.kind, actor_id: actor.id, recorded_by: "coordinator", policy_version: "candidate-scope-fixture/v1"))
        end
        source = event_store.append(streams.candidate(candidate_id), physical).last
        result = count.call_command(count_command(statistics_id, source))
        expect(result.failure.code).to eq(:projection_statistics_source_mismatch)
        expect(loader.counted?(statistics_id, candidate_id)).to be(false)
      end
    expect(history(statistics_id).map(&:id)).to eq(before)
  end

  it "retains more than one hundred accepted checkpoints as an absolute fact, not a clipped detail count" do
    reservation = arrange
    statistics_id = ensure_statistics.call_command(ensure_command).value!
    101.times do |index|
      source = submit(reservation, index + 1)
      expect(count.call_command(count_command(statistics_id, source))).to be_success
    end
    expect(loader.state(statistics_id).checkpoints_number).to eq(101)
    expect(history(statistics_id).count { _1.type == "CandidateCheckpointCounted" }).to eq(101)
  end

  def arrange
    WorkIntentionOperationScenario.start_attempts(event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ])
    WorkIntentionOperationScenario.declare(event_store:,
      paths: [ { kind: "file", path: "lib/checkpoint.rb", base_blob_oid: "c" * 40 } ])
  end

  def submit(reservation, index)
    result = Coordinator::Write::Operations::ExecuteSubmitCandidate.new(event_store:).call(
      command_id: SecureRandom.uuid_v7, actor: { kind: "agent", id: "agent-a" },
      candidate_id: "CAN-STATS-#{index}", change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A", attempt_id: "A-LSE-A",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, target_branch: "main",
      base_commit_oid: "a" * 40, head_commit_oid: index.to_s(16).rjust(40, "d"),
      checkpoint_kind: Coordinator::Write::Types::CANDIDATE_CHECKPOINT_KINDS.fetch((index - 1) % 3),
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

  def ensure_command(repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID)
    Coordinator::Write::Commands::EnsureChangeSetRepositoryCheckpointStatistics.new(
      command_id: SecureRandom.uuid_v7, actor:, statistics_id: SecureRandom.uuid_v7,
      change_set_id: "CS-LSE", repository_id:)
  end

  def count_command(statistics_id, source)
    Coordinator::Write::Commands::CountCandidateCheckpoint.new(command_id: SecureRandom.uuid_v7, actor:,
      statistics_id:, source_event: Coordinator::Write::EventReference.new(event_id: source.id, type: source.type,
        stream_context: source.stream.context, stream_name: source.stream.stream_name,
        stream_id: source.stream.stream_id, stream_revision: source.stream_revision))
  end

  def history(statistics_id)
    event_store.read(streams.checkpoint_statistics(statistics_id), Coordinator::Write::EventReadCriteria.new(
      event_types: Coordinator::Write::EventQueries::CHECKPOINT_STATISTICS_CONTROL.event_types,
      maximum_count: 300, direction: :asc))
  end

  def observations(calls, queries)
    TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.defined_class == Coordinator::Write::EventStore

      next unless frame.path.end_with?("/lib/coordinator/write/event_store.rb")

      calls << frame.method_id
      queries << frame.binding.local_variable_get(:criteria) if frame.method_id == :read
    end
  end

  def concurrently(values)
    ready, release = Queue.new, Queue.new
    workers = values.map { |value| Thread.new { ready << true; release.pop; yield value } }
    workers.length.times { ready.pop }
    workers.length.times { release << true }
    workers.map(&:value)
  ensure
    workers&.each(&:join)
  end
end
