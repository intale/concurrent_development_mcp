# frozen_string_literal: true

# Real application calls, official SDK adapters and no timing assertions.
# Provider/fixture setup is outside the measured interval. The first pair warms
# each path; five alternating pairs avoid always favoring one execution order.
RSpec.describe "Observability overhead" do
  let(:runtime) { Coordinator::Shared::Observability::Runtime }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  after { runtime.shutdown }

  it "preserves a real MCP read response with and without instrumentation", :read_model do
    runtime.shutdown
    skill = FactoryBot.create(:coordinator_read_skill)
    FactoryBot.create(:coordinator_read_skill_revision, skill:)
    http = ActionDispatch::Integration::Session.new(Rails.application)
    http.host! "localhost"
    request = JSON.generate(
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: {
        name: "skill_list", arguments: { name: skill.name, limit: 10 },
        _meta: {
          "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
          "io.modelcontextprotocol/clientCapabilities" => { extensions: { "io.modelcontextprotocol/tasks" => {} } }
        }
      }
    )
    original = nil
    measure_samples("mcp_skill_list") do |enabled, _sample|
      elapsed, = measure(enabled) do
        http.post("/mcp", params: request, headers: {
          "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
          "MCP-Protocol-Version" => "2026-07-28", "Mcp-Method" => "tools/call", "Mcp-Name" => "skill_list"
        })
      end
      expect(http.response.status).to eq(200)
      response = JSON.parse(http.response.body)
      expect(response.dig("result", "structuredContent", "data", "page", "items").sole.fetch("name")).to eq(skill.name)
      original ||= response
      expect(response).to eq(original)
      elapsed
    end
  end

  it "preserves real batch execution and idempotent redelivery", :event_store do
    handler = Coordinator::Processes::Subscriptions::OperationBatchRunner.new(
      handler: Coordinator::Processes::ProcessManagers::OperationBatchRunner.new(event_store:)
    ).handler
    measure_samples("batch_two_skill_items") do |enabled, sample|
      runtime.shutdown
      command = Coordinator::Write::Operations::PrepareCreateSkillPublishBatch.new.call(
        command_id: "overhead-batch-#{enabled}-#{sample}", actor: { kind: "agent", id: "overhead-agent" },
        batch_id: SecureRandom.uuid_v7,
        items: 2.times.map do |index|
          {
            command_id: "overhead-item-#{enabled}-#{sample}-#{index}", actor: { kind: "agent", id: "overhead-agent" },
            name: "overhead-skill-#{enabled}-#{sample}-#{index}", scope: "project:overhead",
            expected_revision: 0, description: "Measured Skill", instructions: "Inspect the complete diff.", assets: []
          }
        end
      ).value!
      expect(Coordinator::Write::Operations::ExecuteOperationBatchCommand.new(event_store:).call_command(command)).to be_success
      created = batch_history(command.batch_id).find { _1.type == "OperationBatchCreated" }
      elapsed, result = measure(enabled) { handler.call(created) }
      expect(result).to be_nil
      history = batch_history(command.batch_id)
      expect(history.last.type).to eq("OperationBatchCompleted")
      expect(history.count { _1.type == "OperationBatchItemSucceeded" }).to eq(2)
      handler.call(created)
      expect(batch_history(command.batch_id).map(&:id)).to eq(history.map(&:id))
      elapsed
    end
  end

  it "preserves a real artifact property projection without changing its stored body or event time", :read_model do
    body = "a" * 1_048_576
    handler = Coordinator::Read::Subscriptions::DevelopmentArtifacts.new(
      handler: Coordinator::Read::Projectors::DevelopmentArtifactsV1.new(event_store:)
    ).handler
    measure_samples("artifact_title_with_1mib_body") do |enabled, sample|
      runtime.shutdown
      artifact = FactoryBot.create(:coordinator_read_development_artifact,
        content_text: body, updated_at: Time.utc(2026, 8, 30, 12))
      event = ProjectionEventFactory.build(
        payload: Coordinator::Write::Events::DevelopmentArtifactTitleChangedV1.new(
          artifact_id: artifact.artifact_id, title: "Measured title"
        ),
        stream: streams.development_artifact(artifact.artifact_id), stream_revision: 1,
        global_position: 300 + sample, policy_version: "development-artifact-repository/v2",
        created_at: Time.utc(2026, 8, 30, 12, 1)
      )
      elapsed, result = measure(enabled) { handler.call(event) }
      expect(result).to be_nil
      artifact.reload
      expect(artifact).to have_attributes(title: "Measured title", content_text: body, updated_at: event.created_at)
      handler.call(event)
      expect(artifact.reload).to have_attributes(title: "Measured title", updated_at: event.created_at)
      elapsed
    end
  end

  def batch_history(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end

  def measure(enabled)
    runtime.shutdown
    session = runtime.configure(environment: "test", env: { "COORDINATOR_OBSERVABILITY_ENABLED" => "true" }) if enabled
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(session.span_exporter.finished_spans).not_to be_empty if session
    [ elapsed, result ]
  end

  def measure_samples(name)
    samples = { false => [], true => [] }
    6.times do |sample|
      order = sample.even? ? [ false, true ] : [ true, false ]
      order.each do |enabled|
        elapsed = yield(enabled, sample)
        samples.fetch(enabled) << elapsed if sample.positive?
      end
    end
    return unless ENV["OBSERVABILITY_OVERHEAD_REPORT"] == "1"

    disabled = samples.fetch(false).sort.fetch(2)
    enabled = samples.fetch(true).sort.fetch(2)
    puts "OBSERVABILITY_OVERHEAD #{JSON.generate(
      path: name, samples_per_mode: 5, disabled_median_ms: (disabled * 1000).round(3),
      enabled_median_ms: (enabled * 1000).round(3), median_delta_ms: ((enabled - disabled) * 1000).round(3),
      mode: 'official_in_memory_adapters', setup_included: false
    )}"
  end
end
