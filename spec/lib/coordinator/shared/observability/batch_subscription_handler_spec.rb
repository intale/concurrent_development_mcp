# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::BatchSubscriptionHandler, observability: true do
  let(:definition) { Coordinator::Read::Subscriptions::Repositories::DEFINITION }
  let(:repository_id) { SecureRandom.uuid_v7 }
  let(:events) do
    stream = Coordinator::Write::StreamFactory.new.repository(repository_id)
    [
      Coordinator::Write::Events::RepositoryRegisteredV2.new(repository_id:, scope: "project:batch", repository_key: "batch"),
      Coordinator::Write::Events::RepositoryDisplayNameChangedV1.new(repository_id:, display_name: "private display name"),
      Coordinator::Write::Events::RepositoryDisplayNameChangedV1.new(repository_id:, display_name: "private replacement")
    ].map.with_index do |payload, index|
      ProjectionEventFactory.build(payload:, stream:, stream_revision: index, global_position: index + 1,
        policy_version: "repository-registration/v1", created_at: Time.now.utc - 60 + index)
    end
  end

  def wrapped(&handler)
    described_class.new(definition:, handler:)
  end

  def points(name)
    telemetry_metrics.select { _1.name == "coordinator.subscription.#{name}" }.flat_map(&:data_points)
  end

  it "delivers the original array once, preserving order and the handler return value" do
    batch = events
    calls = 0
    returned = wrapped do |received|
      calls += 1
      expect(received).to equal(batch)
      expect(received.map(&:stream_revision)).to eq([ 0, 1, 2 ])
      Coordinator::Shared::Observability::Runtime.current.tracer.start_span("batch child").finish
      :original
    end.call(batch)

    expect(returned).to eq(:original)
    expect(calls).to eq(1)
    span = telemetry_spans.find { _1.name.start_with?("subscription ") }
    expect(span.kind).to eq(:consumer)
    expect(span.attributes).to include(
      "event.type" => "batch", "event.count" => "3",
      "event.types" => "RepositoryDisplayNameChanged,RepositoryRegistered", "outcome" => "ok"
    )
    expect(span.attributes.to_s).not_to include("private", repository_id)
    expect(telemetry_spans.find { _1.name == "batch child" }.parent_span_id).to eq(span.span_id)
    expect(points("started").sum(&:value)).to eq(1)
    delivered = points("delivered").to_h { [ _1.attributes.fetch("event.type"), _1.value ] }
    expect(delivered).to eq("RepositoryRegistered" => 1, "RepositoryDisplayNameChanged" => 2)
    expect(points("delivery.age").sole.count).to eq(1)
    expect(points("delivery.age").sole.sum).to be >= 60
  end

  it "counts native redelivery as another callback and actual delivered events, not durable facts" do
    batch = events
    handler = wrapped { |_received| nil }

    2.times { handler.call(batch) }

    expect(points("started").sum(&:value)).to eq(2)
    expect(points("completed").sum(&:value)).to eq(2)
    expect(points("delivered").sum(&:value)).to eq(6)
    expect(points("in.flight").sole.value).to eq(0)
    expect(points("oldest.in.flight").sole.value).to eq(0.0)
  end

  it "propagates the exact failure for native retry without leaking its message or event bodies" do
    error = RuntimeError.new("private failure detail")

    expect { wrapped { |_received| raise error }.call(events) }.to raise_error { expect(_1).to equal(error) }

    expect(telemetry_spans.last.attributes).to include("outcome" => "error", "exception.type" => "RuntimeError")
    expect(telemetry_spans.last.attributes.to_s).not_to include(error.message, "private display name")
    expect(points("in.flight").sole.value).to eq(0)
    expect(points("oldest.in.flight").sole.value).to eq(0.0)
    expect(OpenTelemetry::Trace.current_span.context.valid?).to be(false)
  end

  it "bounds unrecognized event types without logging their arbitrary names" do
    batch = events
    batch.last.type = "private-unregistered-type"

    wrapped { |_received| nil }.call(batch)

    expect(points("delivered").map { _1.attributes.fetch("event.type") }).to include("unknown")
    expect(telemetry_spans.last.attributes.fetch("event.types")).to include("unknown")
    expect(telemetry_spans.last.attributes.to_s).not_to include("private-unregistered-type")
  end

  it "represents a thousand-event callback without a thousand spans or invocation samples" do
    batch = Array.new(1000, events.first)

    wrapped { |received| expect(received).to equal(batch); nil }.call(batch)

    expect(telemetry_spans.length).to eq(1)
    expect(points("started").sum(&:value)).to eq(1)
    expect(points("delivered").sum(&:value)).to eq(1000)
  end

  it "calls a disabled handler once without instrumentation" do
    batch = events
    Coordinator::Shared::Observability::Runtime.shutdown

    expect(wrapped { |received| expect(received).to equal(batch); :original }.call(batch)).to eq(:original)
  end
end
