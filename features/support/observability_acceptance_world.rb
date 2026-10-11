# frozen_string_literal: true

module ObservabilityAcceptanceWorld
  PRIVATE_INSTRUCTIONS = "private-observability-instructions: inspect the complete diff".freeze
  PRIVATE_AGENT = "private-observability-agent".freeze
  SKILL_NAME = "observability-review".freeze
  SKILL_SCOPE = "project:observability-acceptance".freeze

  def reset_observed_telemetry
    Coordinator::Shared::Observability::Runtime.shutdown
    Coordinator::Shared::Observability::Runtime.configure(
      environment: "test", env: { "COORDINATOR_OBSERVABILITY_ENABLED" => "true" }
    )
  end

  def observed_skill_publication(command_id:)
    submit_skill_task(
      name: SKILL_NAME, scope: SKILL_SCOPE, command_id:, expected_revision: 0,
      instructions: PRIVATE_INSTRUCTIONS, client_id: PRIVATE_AGENT
    )
  end

  def observed_spans
    Coordinator::Shared::Observability::Runtime.current.span_exporter.finished_spans
  end

  def observed_metrics
    reader = Coordinator::Shared::Observability::Runtime.current.metric_reader
    reader.reset
    reader.pull
    reader.metric_snapshots
  end

  def assert_observed_outcome(method:, outcome:, tool: "none")
    labels = { "rpc.method" => method, "mcp.tool.name" => tool, "outcome" => outcome }
    points = observed_metrics.select { _1.name == "coordinator.mcp.completed" }.flat_map(&:data_points)
    assert_acceptance(points.any? { _1.attributes == labels && _1.value >= 1 }, "Missing MCP measurement: #{labels.inspect}")
  end

  def assert_observed_privacy_and_dimensions
    stop_live_subscriptions
    definitions = Coordinator::Shared::Observability::Contract.metrics.to_h { [ _1.name, _1 ] }
    metrics = observed_metrics
    metrics.each do |metric|
      allowed = definitions.fetch(metric.name).dimensions
      metric.data_points.each do |point|
        assert_acceptance((point.attributes.keys - allowed).empty?, "Unbounded dimensions on #{metric.name}")
      end
    end
    idle = metrics.select { _1.name.end_with?("in.flight") }.flat_map(&:data_points)
    assert_acceptance(!idle.empty? && idle.all? { _1.value.zero? }, "Finished invocations must leave zero in-flight state")
    exported = [ observed_spans.map { [ _1.name, _1.attributes, _1.events ] },
                 metrics.map { _1.data_points.map(&:attributes) } ].inspect
    private_values = [ PRIVATE_INSTRUCTIONS, PRIVATE_AGENT, @observed_publication.fetch(:task_id) ]
    private_values.each { |value| assert_acceptance(!exported.include?(value), "Private coordination value was exported") }
  end
end

World(ObservabilityAcceptanceWorld)

Before("@observability") do
  reset_observed_telemetry
end

After("@observability") do
  stop_live_subscriptions
  Coordinator::Shared::Observability::Runtime.shutdown
end
