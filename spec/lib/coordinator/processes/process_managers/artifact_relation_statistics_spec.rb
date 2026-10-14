# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::ArtifactRelationStatistics, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:manager) { described_class.new(event_store:) }
  let(:loader) { Coordinator::Write::ProjectionStatistics::ArtifactRelationsLoader.new(event_store:) }
  let(:reconcile) { Coordinator::Write::Operations::ExecuteReconcileDevelopmentArtifactRelationsNumber.new(event_store:) }
  let(:actor) { Coordinator::Write::Commands::Actor.new(kind: "agent", id: "statistics-process-spec") }

  it "uses stable process decisions and native immediate-parent tracing on replay" do
    artifact_id, sources = arrange_sources(1)
    source = sources.first
    expect(manager.call(source)).to be_nil
    statistics_id = registered_identity(artifact_id)
    events = history(statistics_id)

    expect(events.map(&:type)).to eq(%w[
      DevelopmentArtifactRelationStatisticsAssigned DevelopmentArtifactRelationsNumberChanged
      DevelopmentArtifactRelationsNumberChanged DevelopmentArtifactRelationsReconciled
    ])
    expect(events.map(&:correlation_id).uniq).to eq([ source.correlation_id ])
    parents = %w[ensure reconcile].to_h do |step_name|
      subject_id = step_name == "ensure" ? artifact_id : statistics_id
      marker = Coordinator::Shared::Markers::CodecV2.new.call(
        purpose: "process-step", components: [
          { dimension: "process-name", value: "artifact-relation-statistics" },
          { dimension: "source-event-id", value: source.id },
          { dimension: "step-name", value: step_name },
          { dimension: "subject-kind", value: "artifact-relation-statistics" },
          { dimension: "subject-id", value: subject_id }
        ]).value!.marker
      parent = event_store.read_global_marked(Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "CoordinatorControl", stream_name: "ProcessStep", event_types: [ "ProcessStepPlanned" ],
        markers: [ marker ], maximum_count: 1, direction: :asc)).sole
      [ parent.id, parent ]
    end
    events.each do |event|
      parent = parents.fetch(event.causation_id)
      expect(parent).to have_attributes(id: event.causation_id, type: "ProcessStepPlanned")
      expect(parent.data.fetch("source_event_id")).to eq(source.id)
      expect(parent.data.fetch("target_command_id")).to eq(event.metadata.fetch("command_id"))
      expect(parent.causation_id).to eq(source.id)
    end

    before = history(statistics_id).map(&:id)
    manager.call(source)
    expect(history(statistics_id).map(&:id)).to eq(before)
  end

  it "records exact retryable failure evidence after real conflicts and repairs on authorized redelivery" do
    artifact_id, sources = arrange_sources(4)
    source = sources.shift
    statistics_id = Coordinator::Write::Operations::ExecuteEnsureDevelopmentArtifactRelationStatistics.new(event_store:)
      .call_command(Coordinator::Write::Commands::EnsureDevelopmentArtifactRelationStatistics.new(
        command_id: SecureRandom.uuid_v7, actor:, artifact_id:, statistics_id: SecureRandom.uuid_v7)).value!
    collisions = 0
    trace = TracePoint.new(:call) do |frame|
      next unless frame.self.equal?(event_store) && frame.method_id == :append &&
                    frame.defined_class == Coordinator::Write::EventStore && sources.any?
      next unless frame.binding.local_variable_get(:events).any? { _1.type == "DevelopmentArtifactRelationsReconciled" }

      other = sources.shift
      collisions += 1
      expect(reconcile.call_command(Coordinator::Write::Commands::ReconcileDevelopmentArtifactRelationsNumber.new(
        command_id: SecureRandom.uuid_v7, actor:, statistics_id:, source_event: reference(other)), caused_by: other)).to be_success
    end
    trace.enable { manager.call(source) }

    expect(collisions).to eq(3)
    failed = history(statistics_id).last
    expect(failed).to have_attributes(type: "DevelopmentArtifactRelationsReconciliationFailed")
    expect(failed.data.fetch("source_event_id")).to eq(source.id)
    expect(failed.data.fetch("failure")).to include(
      "reason_code" => "concurrency_conflict", "retryable" => true, "effects_committed" => false, "attempts" => 3)
    expect(loader.reconciled?(statistics_id, source.id)).to be(false)
    expect(failed.correlation_id).to eq(source.correlation_id)

    manager.call(source)
    expect(loader.reconciled?(statistics_id, source.id)).to be(true)
    expect(history(statistics_id).last).to have_attributes(type: "DevelopmentArtifactRelationsReconciled")
    before = history(statistics_id).map(&:id)
    manager.call(source)
    expect(history(statistics_id).map(&:id)).to eq(before)
  ensure
    trace&.disable
  end

  def arrange_sources(count)
    artifact_id = capture("source")
    sources = count.times.map do |index|
      target = capture("target-#{index}")
      result = Coordinator::Write::Operations::ExecuteDeclareDevelopmentArtifactRelation.new(event_store:).call(
        command_id: SecureRandom.uuid_v7, actor: actor.to_h, source_artifact_id: artifact_id,
        relation: "references", target: { kind: "artifact", id: target }, attributes: { path: "#{index}.md" })
      expect(result).to be_success
      emitted = result.value!.emitted_events.first
      event_store.read_at(streams.development_artifact_relation(emitted.stream_id), emitted.stream_revision)
    end
    [ artifact_id, sources ]
  end

  def capture(title)
    result = Coordinator::Write::Operations::ExecuteCaptureDevelopmentArtifact.new(event_store:).call(
      command_id: SecureRandom.uuid_v7, actor: actor.to_h, scope: "project:statistics-process-spec", title:,
      kind: "documentation", labels: [], content: { encoding: "utf-8", media_type: "text/plain", text: title },
      source: { kind: "generated", locator: title, revision: nil, collector: "statistics-process-spec",
        observed_at: "2026-10-13T12:00:00.000000Z" })
    expect(result).to be_success
    result.value!.data.artifact_id
  end

  def reference(event)
    Coordinator::Write::EventReference.new(event_id: event.id, type: event.type,
      stream_context: event.stream.context, stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id, stream_revision: event.stream_revision)
  end

  def registered_identity(artifact_id)
    result = Coordinator::Write::NaturalKeys::Registry.new(event_store:).find(selector: loader.selector(artifact_id),
      identity_from: ->(event) { event.data.fetch("statistics_id") })
    result.value!.identity
  end

  def history(statistics_id)
    event_store.read(streams.development_artifact_relation_statistics(statistics_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_RELATION_STATISTICS_CONTROL.event_types,
        maximum_count: 32, direction: :asc))
  end
end
