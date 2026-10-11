# frozen_string_literal: true

RSpec.describe Coordinator::Mcp::Tasks::Server, :event_store, observability: true do
  let(:server) { Coordinator::Container["mcp.server"] }

  def request(method, params = {})
    JSON.parse(JSON.generate(jsonrpc: "2.0", id: 1, method:, params:), symbolize_names: true)
  end

  def capable(params)
    params.merge("_meta" => {
      "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities" => { "extensions" => { "io.modelcontextprotocol/tasks" => {} } }
    })
  end

  it "captures both public native entrypoints exactly once" do
    expect(server.handle(request("ping"))).to include(result: {})
    expect(JSON.parse(server.handle_json(JSON.generate(request("tools/list")))).fetch("result").fetch("tools")).not_to be_empty

    expect(telemetry_spans.map(&:name)).to eq([ "mcp ping", "mcp tools/list" ])
    metric = telemetry_metrics.find { _1.name == "coordinator.mcp.completed" }
    expect(metric.data_points.sum(&:value)).to eq(2)
  end

  it "covers every registry tool even when the client lacks the required capability" do
    Coordinator::Mcp::ToolRegistry.all.each do |tool|
      result = server.handle(request("tools/call", "name" => tool.tool_name, "arguments" => {}))
      expect(result.dig(:error, :code)).to eq(-32_003)
    end
    expect(telemetry_spans.map { _1.attributes.fetch("mcp.tool.name") }).to contain_exactly(*Coordinator::Mcp::ToolRegistry.all.map(&:tool_name))
    expect(telemetry_spans.map { _1.attributes.fetch("outcome") }.uniq).to eq([ "denied" ])
  end

  it "bounds unknown caller-controlled labels and retains native parse/validation errors" do
    result = server.handle(request("private-method"))
    expect(result.dig(:error, :code)).to eq(-32_601)
    server.handle(request("tools/call", capable("name" => "private-tool", "arguments" => { "secret" => "private-value" })))
    expect(JSON.parse(server.handle_json("invalid private JSON")).dig("error", "code")).to eq(-32_700)
    attributes = telemetry_spans.map(&:attributes)
    expect(attributes.first).to include("rpc.method" => "unknown", "outcome" => "not_found")
    expect(attributes[1]).to include("mcp.tool.name" => "unknown")
    expect(attributes.last).to include("rpc.method" => "unknown", "outcome" => "invalid")
    expect(attributes.to_s).not_to match(/private/)
  end

  it "records valid tool names for argument-validation failures and notifications" do
    invalid = server.handle(request("tools/call", capable("name" => "resource_resolve", "arguments" => {})))
    expect(invalid.dig(:result, :isError)).to be(true)
    expect(server.handle(request("ping").except(:id))).to be_nil
    expect(telemetry_spans.map { _1.attributes.fetch("outcome") }).to eq(%w[error ok])
    expect(telemetry_spans.first.attributes.fetch("mcp.tool.name")).to eq("resource_resolve")
  end

  it "keeps labels and context separate for simultaneous clients on one server" do
    ready = Queue.new
    start = Queue.new
    threads = %w[skill_get decision_get].map do |name|
      Thread.new do
        ready << true
        start.pop
        20.times { server.handle(request("tools/call", "name" => name, "arguments" => {})) }
        OpenTelemetry::Trace.current_span.context.valid?
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value)).to eq([ false, false ])
    names = telemetry_spans.map { _1.attributes.fetch("mcp.tool.name") }.tally
    expect(names).to eq("skill_get" => 20, "decision_get" => 20)
    metric = telemetry_metrics.find { _1.name == "coordinator.mcp.in.flight" }
    expect(metric.data_points.map(&:value)).to eq([ 0, 0 ])
  ensure
    threads&.each(&:join)
  end

  it "separates durable mutation acceptance from pending Task lookup" do
    args = { "command_id" => "observability-acceptance", "actor" => { "kind" => "agent", "id" => "private-agent" },
      "repository_id" => "018f0f78-8e7d-7000-8000-000000000001", "kind" => "file", "path" => "private/path.rb" }
    accepted = server.handle(request("tools/call", capable("name" => "resource_resolve", "arguments" => args)))
    expect(accepted.dig(:result, :resultType)).to eq("task")
    task_id = accepted.dig(:result, :taskId)
    pending = server.handle(request("tasks/get", capable("taskId" => task_id)))
    expect(pending.dig(:result, :status)).to eq("working")

    expect(telemetry_spans.map { _1.attributes.fetch("outcome") }).to eq(%w[accepted pending])
    expect(telemetry_spans.map(&:attributes).to_s).not_to match(/private-agent|private\/path|#{task_id}/)
  end

  it "does not produce instrumentation when disabled" do
    Coordinator::Shared::Observability::Runtime.shutdown
    expect(server.handle(request("ping"))).to include(result: {})
    expect(Coordinator::Shared::Observability::Runtime.current).to be_nil
  end
end
