# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::SubscriptionHandler, :event_store, observability: true do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:definition) { Coordinator::Read::Subscriptions::Repositories::DEFINITION }
  let(:event) do
    repository_id = RepositoryScenario.register(event_store:)
    event_store.read(
      Coordinator::Write::StreamFactory.new.repository(repository_id),
      Coordinator::Write::EventReadCriteria.new(event_types: [ "RepositoryRegistered" ], maximum_count: 1, direction: :asc)
    ).first
  end

  def wrapped(&handler)
    described_class.new(definition:, handler:)
  end

  def points(name)
    telemetry_metrics.select { _1.name == "coordinator.subscription.#{name}" }.flat_map(&:data_points)
  end

  it "decorates every real registration without changing filters or subscription identity" do
    %w[process_managers task_results read_models].each do |set|
      registrations = Coordinator::Container["subscription_registrations.#{set}"]
      registrations.each do |registration|
        expect(registration.handler).to be_a(described_class)
        expect(registration.handler.definition).to equal(registration.definition)
      end
    end
  end

  it "preserves the exact event and return value, with bounded envelope diagnostics" do
    persisted = event
    calls = 0
    returned = wrapped do |received|
      calls += 1
      expect(received).to equal(persisted)
      Coordinator::Shared::Observability::Runtime.current.tracer.start_span("handler child").finish
      :original
    end.call(persisted)

    expect(returned).to eq(:original)
    expect(calls).to eq(1)
    span = telemetry_spans.find { _1.name.start_with?("subscription ") }
    expect(span.kind).to eq(:consumer)
    expect(span.attributes).to eq(
      "subscription.set" => definition.set_name, "subscription.name" => definition.subscription_name,
      "event.type" => persisted.type, "outcome" => "ok"
    )
    expect(telemetry_spans.find { _1.name == "handler child" }.parent_span_id).to eq(span.span_id)
    expect(points("in.flight").first.value).to eq(0)
    expect(points("delivery.age").first.sum).to be >= 0
    expect(points("oldest.in.flight").first.value).to eq(0.0)
  end

  it "reports advancing unfinished age while a real handler is blocked and clears it afterward" do
    persisted = event
    entered = Queue.new
    released = Queue.new
    handler = wrapped { |received| entered << received.id; released.pop; :original }
    thread = Thread.new { handler.call(persisted) }
    expect(entered.pop(timeout: 5)).to eq(persisted.id)

    first_age = points("oldest.in.flight").first.value
    expect(points("in.flight").first.value).to eq(1)
    expect(points("oldest.in.flight").first.value).to be > first_age
    expect(telemetry_spans.select { _1.name.start_with?("subscription ") }).to be_empty
    released << true
    expect(thread.value).to eq(:original)
    expect(points("oldest.in.flight").first.value).to eq(0.0)
    expect(points("in.flight").first.value).to eq(0)
  ensure
    released << true if thread&.alive?
    thread&.join
  end

  it "propagates failures for native retry without leaking event data or exception messages" do
    error = RuntimeError.new("private handler details")
    handler = wrapped { |_received| raise error }
    expect { handler.call(event) }.to raise_error { expect(_1).to equal(error) }
    expect(telemetry_spans.last.attributes).to include("outcome" => "error", "exception.type" => "RuntimeError")
    expect(telemetry_spans.last.attributes.to_s).not_to include(error.message)
    expect(points("in.flight").first.value).to eq(0)
    expect(points("oldest.in.flight").first.value).to eq(0.0)
    expect(OpenTelemetry::Trace.current_span.context.valid?).to be(false)
  end

  it "does not instrument disabled delivery or assume a returned value means business success" do
    persisted = event
    Coordinator::Shared::Observability::Runtime.shutdown
    expect(wrapped { |_received| :business_denied }.call(persisted)).to eq(:business_denied)
    expect(Coordinator::Shared::Observability::Runtime.current).to be_nil
  end
end
