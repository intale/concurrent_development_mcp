# frozen_string_literal: true

RSpec.describe Coordinator::Shared::Observability::Session, observability: true do
  subject(:session) { Coordinator::Shared::Observability::Runtime.current }

  it "uses SDK test adapters and associates process resource identity with both signals" do
    expect(session.span_exporter).to be_a(OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter)
    expect(session.metric_reader).to be_a(OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter)
    expect(session.meter_provider.resource).to eq(session.tracer_provider.resource)
    expect(session.tracer_provider.resource.attribute_enumerator.to_h).to include(
      "service.name" => "concurrent-development-coordinator", "service.instance.id" => session.instance_id,
      "deployment.environment.name" => "test", "coordinator.process.role" => "web"
    )
  end

  it "records real SDK spans and cumulative metrics with only allowed dimensions" do
    span = session.tracer.start_span("mcp tools/list", attributes: { "rpc.method" => "tools/list" })
    labels = { "rpc.method" => "tools/list", "mcp.tool.name" => "none", "payload" => "private" }.freeze
    session.record(:mcp_started, 1, attributes: labels)
    session.record(:mcp_duration, 0.025, attributes: labels.merge("outcome" => "ok"))
    span.finish
    session.force_flush

    expect(telemetry_spans.map(&:name)).to eq([ "mcp tools/list" ])
    counter = telemetry_metrics.find { _1.name == "coordinator.mcp.started" }
    expect(counter.aggregation_temporality).to eq(:cumulative)
    expect(counter.data_points.first.value).to eq(1)
    expect(counter.data_points.first.attributes).to eq("rpc.method" => "tools/list", "mcp.tool.name" => "none")
    session.metric_reader.pull
    duration = session.metric_reader.metric_snapshots.find { _1.name == "coordinator.mcp.duration" }
    expect(duration.data_points.first.explicit_bounds).to eq(Coordinator::Shared::Observability::Contract::DURATION_BOUNDARIES)
  end

  it "reports independent bounded observable series, including a zero after completion" do
    values = { "one" => 1.0, "two" => 2.0 }
    values.each_key do |name|
      session.register_observer(:subscription_oldest_in_flight,
        attributes: { "subscription.set" => "test", "subscription.name" => name, "event.type" => "Test" }) { values.fetch(name) }
    end
    points = telemetry_metrics.select { _1.name == "coordinator.subscription.oldest.in.flight" }.flat_map(&:data_points)
    expect(points.map { [ _1.attributes.fetch("subscription.name"), _1.value ] }.to_h).to eq(values)

    values["one"] = 0.0
    points = telemetry_metrics.select { _1.name == "coordinator.subscription.oldest.in.flight" }.flat_map(&:data_points)
    expect(points.find { _1.attributes.fetch("subscription.name") == "one" }.value).to eq(0.0)
  end
end
