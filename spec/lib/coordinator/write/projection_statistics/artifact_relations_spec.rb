# frozen_string_literal: true

RSpec.describe "Artifact relation statistics", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "agent", id: "relation-statistics-spec") }
  let(:loader) { Coordinator::Write::ProjectionStatistics::ArtifactRelationsLoader.new(event_store:) }
  let(:ensure_statistics) { Coordinator::Write::Operations::ExecuteEnsureDevelopmentArtifactRelationStatistics.new(event_store:) }
  let(:reconcile) { Coordinator::Write::Operations::ExecuteReconcileDevelopmentArtifactRelationsNumber.new(event_store:) }
  let(:record_failure) do
    Coordinator::Write::Operations::ExecuteRecordDevelopmentArtifactRelationsReconciliationFailure.new(event_store:)
  end

  it "allocates one canonical UUID with an atomic initial association and zero numbers under concurrency" do
    artifact_id = capture_artifact("owner")
    before = artifact_history(artifact_id).map(&:id)
    commands = Array.new(2) { ensure_command(artifact_id) }
    results = concurrently(commands) { ensure_statistics.call_command(_1) }

    expect(results).to all(be_success)
    identities = results.map(&:value!)
    expect(identities.uniq.length).to eq(1)
    expect(commands.map(&:statistics_id)).to include(identities.first)
    events = statistics_history(identities.first)
    expect(events.map(&:type)).to eq(%w[
      DevelopmentArtifactRelationStatisticsAssigned DevelopmentArtifactRelationsNumberChanged
    ])
    expect(events.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(events.first.data).to eq("statistics_id" => identities.first, "artifact_id" => artifact_id)
    expect(events.last.data).to eq("artifact_id" => artifact_id,
      "active_relations_number" => 0, "lifetime_relations_number" => 0)
    expect(events.map(&:correlation_id).uniq.length).to eq(1)
    expect(artifact_history(artifact_id).map(&:id)).to eq(before)

    calls = []
    trace = store_calls(calls)
    replay = trace.enable { ensure_statistics.call_command(ensure_command(artifact_id)) }
    expect(replay.value!).to eq(identities.first)
    expect(calls).not_to include(:multiple, :append)
  ensure
    trace&.disable
  end

  it "denies an absent owner without allocating a statistics stream" do
    command = ensure_command(SecureRandom.uuid_v7)
    result = ensure_statistics.call_command(command)

    expect(result.failure.code).to eq(:development_artifact_not_found)
    expect(statistics_history(command.statistics_id)).to be_empty
  end

  it "assigns absolute numbers once with exact tracing and bounded source reads" do
    artifact_id = capture_artifact("owner")
    source = declare(artifact_id, capture_artifact("target")).first
    statistics_id = ensure_statistics.call_command(ensure_command(artifact_id), caused_by: source).value!
    command = reconcile_command(statistics_id, source)
    calls = []
    criteria = []
    trace = store_calls(calls, criteria:)
    result = trace.enable { reconcile.call_command(command, caused_by: source) }

    expect(result).to be_success
    expect(calls.first).to eq(:read_grouped)
    expect(calls).not_to include(:multiple)
    expect(criteria.map(&:event_types)).to eq([ loader.class::SOURCE_TYPES ])
    expect(criteria.first).to have_attributes(markers: [ "development-artifact:#{artifact_id}" ], maximum_count: 512)
    events = statistics_history(statistics_id).last(2)
    expect(events.map(&:type)).to eq(%w[DevelopmentArtifactRelationsNumberChanged DevelopmentArtifactRelationsReconciled])
    expect(events.first.data).to eq("artifact_id" => artifact_id,
      "active_relations_number" => 1, "lifetime_relations_number" => 1)
    expect(events.last.data).to eq("statistics_id" => statistics_id, "source_event_id" => source.id)
    expect(events.map(&:causation_id)).to eq([ source.id, source.id ])
    expect(events.map(&:correlation_id)).to eq([ source.correlation_id, source.correlation_id ])
    before = statistics_history(statistics_id).map(&:id)
    expect(reconcile.call_command(command, caused_by: source).value!).to be_nil
    expect(statistics_history(statistics_id).map(&:id)).to eq(before)
  ensure
    trace&.disable
  end

  it "recomputes supersession and replacement from authoritative membership despite reversed delivery" do
    artifact_id = capture_artifact("owner")
    original = declare(artifact_id, capture_artifact("first")).first
    replacement = declare(artifact_id, capture_artifact("second"),
      supersedes: { relation_id: original.stream.stream_id, reason: "Replace reference" })
    statistics_id = ensure_statistics.call_command(ensure_command(artifact_id)).value!

    (replacement.reverse + [ original ]).each do |source|
      expect(reconcile.call_command(reconcile_command(statistics_id, source), caused_by: source)).to be_success
    end

    expect(loader.state(statistics_id)).to have_attributes(active_relations_number: 1, lifetime_relations_number: 2)
    history = statistics_history(statistics_id)
    expect(history.select { _1.type == "DevelopmentArtifactRelationsNumberChanged" }.map(&:data)).to eq([
      { "artifact_id" => artifact_id, "active_relations_number" => 0, "lifetime_relations_number" => 0 },
      { "artifact_id" => artifact_id, "active_relations_number" => 1, "lifetime_relations_number" => 2 }
    ])
    expect(history.select { _1.type == "DevelopmentArtifactRelationsReconciled" }.length).to eq(3)
  end

  it "converges concurrent different sources without losing updates or recounting a source" do
    artifact_id = capture_artifact("owner")
    sources = [ declare(artifact_id, capture_artifact("first")).first,
      declare(artifact_id, capture_artifact("second")).first ]
    statistics_id = ensure_statistics.call_command(ensure_command(artifact_id)).value!
    commands = sources.map { reconcile_command(statistics_id, _1) }
    results = concurrently(commands) { reconcile.call_command(_1) }

    expect(results).to all(be_success)
    expect(loader.state(statistics_id)).to have_attributes(active_relations_number: 2, lifetime_relations_number: 2)
    before = statistics_history(statistics_id).map(&:id)
    commands.each { expect(reconcile.call_command(_1).value!).to be_nil }
    expect(statistics_history(statistics_id).map(&:id)).to eq(before)
    expect(statistics_history(statistics_id).count { _1.type == "DevelopmentArtifactRelationsReconciled" }).to eq(2)
  end

  it "denies a source from another owner without changing any numbers" do
    statistics_id = ensure_statistics.call_command(ensure_command(capture_artifact("owner"))).value!
    foreign = declare(capture_artifact("other"), capture_artifact("target")).first
    before = statistics_history(statistics_id).map(&:id)
    result = reconcile.call_command(reconcile_command(statistics_id, foreign), caused_by: foreign)

    expect(result.failure.code).to eq(:projection_statistics_source_mismatch)
    expect(statistics_history(statistics_id).map(&:id)).to eq(before)
  end

  it "records failure evidence idempotently and allows the same source to reconcile later" do
    artifact_id = capture_artifact("owner")
    source = declare(artifact_id, capture_artifact("target")).first
    statistics_id = ensure_statistics.call_command(ensure_command(artifact_id)).value!
    failure = Coordinator::Write::Commands::RecordDevelopmentArtifactRelationsReconciliationFailure.new(
      command_id: SecureRandom.uuid_v7, actor:, statistics_id:, source_event: reference(source),
      failure: Coordinator::Write::Tasks::ExecutionFailureV1.new(
        failed_step: "reconcile-artifact-relations", reason_code: "concurrency_conflict",
        reason: "A later retry may succeed", retryable: true, effects_committed: false, attempts: 3))

    expect(record_failure.call_command(failure, caused_by: source)).to be_success
    before = statistics_history(statistics_id).map(&:id)
    expect(record_failure.call_command(failure, caused_by: source).value!).to be_nil
    expect(statistics_history(statistics_id).map(&:id)).to eq(before)
    expect(loader.reconciled?(statistics_id, source.id)).to be(false)
    expect(loader.state(statistics_id).active_relations_number).to eq(0)
    expect(statistics_history(statistics_id).last).to have_attributes(
      type: "DevelopmentArtifactRelationsReconciliationFailed", causation_id: source.id,
      correlation_id: source.correlation_id)

    expect(reconcile.call_command(reconcile_command(statistics_id, source), caused_by: source)).to be_success
    expect(loader.state(statistics_id).active_relations_number).to eq(1)
    expect(loader.reconciled?(statistics_id, source.id)).to be(true)
    repaired = statistics_history(statistics_id).map(&:id)
    another_failure = failure.new(command_id: SecureRandom.uuid_v7)
    expect(record_failure.call_command(another_failure, caused_by: source).value!).to be_nil
    expect(statistics_history(statistics_id).map(&:id)).to eq(repaired)
  end

  it "returns an explicit retryable failure after three real wrong-revision races without acknowledging the source" do
    artifact_id = capture_artifact("owner")
    sources = 4.times.map { |index| declare(artifact_id, capture_artifact("target-#{index}")).first }
    source = sources.shift
    statistics_id = ensure_statistics.call_command(ensure_command(artifact_id)).value!
    interferences = []
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.method_id == :append &&
                    frame.defined_class == Coordinator::Write::EventStore && sources.any?

      interfering = sources.shift
      interferences << reconcile.call_command(reconcile_command(statistics_id, interfering), caused_by: interfering)
    end
    result = trace.enable { reconcile.call_command(reconcile_command(statistics_id, source), caused_by: source) }

    expect(interferences.length).to eq(3)
    expect(interferences).to all(be_success)
    expect(result.failure).to have_attributes(code: :concurrency_conflict)
    expect(result.failure.message).to include("three attempts", "retried")
    expect(loader.reconciled?(statistics_id, source.id)).to be(false)
    expect(loader.state(statistics_id)).to have_attributes(active_relations_number: 4, lifetime_relations_number: 4)
    expect(statistics_history(statistics_id).count { _1.type == "DevelopmentArtifactRelationsReconciled" }).to eq(3)
  ensure
    trace&.disable
  end

  def ensure_command(artifact_id)
    Coordinator::Write::Commands::EnsureDevelopmentArtifactRelationStatistics.new(
      command_id: SecureRandom.uuid_v7, actor:, artifact_id:, statistics_id: SecureRandom.uuid_v7)
  end

  def reconcile_command(statistics_id, source)
    Coordinator::Write::Commands::ReconcileDevelopmentArtifactRelationsNumber.new(
      command_id: SecureRandom.uuid_v7, actor:, statistics_id:, source_event: reference(source))
  end

  def reference(event)
    Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
      stream_context: event.stream.context, stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id, stream_revision: event.stream_revision)
  end

  def capture_artifact(label)
    result = Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:).call(
      command_id: SecureRandom.uuid_v7, actor: actor.to_h, scope: "project:statistics-spec",
      title: label, kind: "documentation", labels: [],
      content: { encoding: "utf-8", media_type: "text/plain", text: label },
      source: { kind: "generated", locator: "statistics:#{label}", revision: nil,
        collector: "statistics-spec", observed_at: "2026-10-13T12:00:00.000000Z" })
    expect(result).to be_success
    result.value!.data.artifact_id
  end

  def declare(source, target, supersedes: nil)
    input = { command_id: SecureRandom.uuid_v7, actor: actor.to_h, source_artifact_id: source,
      relation: "references", target: { kind: "artifact", id: target }, attributes: { path: "#{target}.md" } }
    input[:supersedes] = supersedes if supersedes
    result = Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:).call(input)
    expect(result).to be_success
    result.value!.emitted_events.map do |event|
      event_store.read_at(stream_reference(event), event.stream_revision)
    end
  end

  def stream_reference(event)
    Coordinator::Write::StreamReference.new(context: event.stream_context,
      stream_name: event.stream_name, stream_id: event.stream_id)
  end

  def artifact_history(artifact_id)
    event_store.read(streams.development_artifact(artifact_id), Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY)
  end

  def statistics_history(statistics_id)
    event_store.read(streams.development_artifact_relation_statistics(statistics_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_RELATION_STATISTICS_CONTROL.event_types,
        maximum_count: 32, direction: :asc))
  end

  def store_calls(calls, criteria: [])
    TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.defined_class == Coordinator::Write::EventStore
      next unless frame.path.end_with?("/lib/coordinator/write/event_store.rb")

      calls << frame.method_id
      criteria << frame.binding.local_variable_get(:criteria) if frame.method_id == :read_global_marked
    end
  end

  def concurrently(values)
    ready = Queue.new
    release = Queue.new
    workers = values.map do |value|
      Thread.new do
        ready << true
        release.pop
        yield value
      end
    end
    workers.length.times { ready.pop }
    workers.length.times { release << true }
    workers.map(&:value)
  ensure
    workers&.each(&:join)
  end
end
