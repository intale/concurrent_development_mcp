# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::Invocation, observability: true do
  let(:labels) { { "rpc.method" => "ping", "mcp.tool.name" => "none" } }
  let(:session) { Coordinator::Shared::Observability::Runtime.current }

  def invocation
    described_class.new(session:, prefix: :mcp, name: "mcp ping", attributes: labels)
  end

  it "preserves the result, records actual runtime and balances in-flight work" do
    result = { value: "private result" }
    calls = 0
    returned = invocation.call(outcome: ->(_value) { "ok" }) do
      calls += 1
      gauge = telemetry_metrics.find { _1.name == "coordinator.mcp.in.flight" }
      expect(gauge.data_points.first.value).to eq(1)
      session.tracer.start_span("child").finish
      result
    end

    expect(returned).to equal(result)
    expect(calls).to eq(1)
    parent = telemetry_spans.find { _1.name == "mcp ping" }
    child = telemetry_spans.find { _1.name == "child" }
    expect(child.parent_span_id).to eq(parent.span_id)
    expect(parent.end_timestamp).to be > parent.start_timestamp
    expect(parent.attributes).to eq(labels.merge("outcome" => "ok"))
    gauge = telemetry_metrics.find { _1.name == "coordinator.mcp.in.flight" }
    expect(gauge.data_points.first.value).to eq(0)
    expect(OpenTelemetry::Trace.current_span.context.valid?).to be(false)
  end

  it "propagates the original business exception without recording its message" do
    error = ArgumentError.new("private payload and credentials")
    expect { invocation.call(outcome: ->(_value) { "ok" }) { raise error } }.to raise_error { expect(_1).to equal(error) }

    span = telemetry_spans.first
    expect(span.attributes).to include("outcome" => "error", "exception.type" => "ArgumentError")
    expect(span.status.ok?).to be(false)
    expect(Array(span.events)).to be_empty
    expect(span.to_s).not_to include(error.message)
    gauge = telemetry_metrics.find { _1.name == "coordinator.mcp.in.flight" }
    expect(gauge.data_points.first.value).to eq(0)
  end

  it "keeps classifier failures outside business execution" do
    calls = 0
    expect do
      result = invocation.call(outcome: ->(_value) { raise KeyError, "private classifier value" }) { calls += 1; :original }
      expect(result).to eq(:original)
    end.to output(/Coordinator telemetry invocation_outcome unavailable \(KeyError\)/).to_stderr
    expect(calls).to eq(1)
    expect(telemetry_spans.first.attributes.fetch("outcome")).to eq("unknown")
    expect(OpenTelemetry::Trace.current_span.context.valid?).to be(false)
  end

  it "preserves work and its exception when the official exporter rejects spans" do
    session.span_exporter.shutdown
    result = Object.new
    calls = 0
    expect(invocation.call(outcome: ->(_value) { "ok" }) { calls += 1; result }).to equal(result)
    error = RuntimeError.new("private business failure")
    expect do
      invocation.call(outcome: ->(_value) { "ok" }) { calls += 1; raise error }
    end.to raise_error { expect(_1).to equal(error) }
    expect(calls).to eq(2)
    expect(telemetry_spans).to be_empty
    gauge = telemetry_metrics.find { _1.name == "coordinator.mcp.in.flight" }
    expect(gauge.data_points.first.value).to eq(0)
    expect(OpenTelemetry::Trace.current_span.context.valid?).to be(false)
  end
end
