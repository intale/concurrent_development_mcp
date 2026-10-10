# frozen_string_literal: true

Given("an independent production deployment with disposable host data") { production_setup }

Then("all four production databases have their application schemas") do
  expected = @production_environment.values_at("DATABASE_NAME", "CACHE_DATABASE_NAME", "QUEUE_DATABASE_NAME", "PG_EVENTSTORE_DATABASE_NAME").sort
  names = production_sql("postgres", "SELECT datname FROM pg_database WHERE datname LIKE '%production%' ORDER BY datname").lines.map(&:strip)
  raise "Missing production databases: #{names}" unless names == expected
  count = Dir.glob(File.join(ProductionDeploymentWorld::ROOT, "db/migrate/*.rb")).length
  raise "Rails migrations incomplete" unless production_sql(expected.find { _1 == "concurrent_development_mcp_production" }, "SELECT count(*) FROM schema_migrations").to_i == count
  raise "Event-store schema absent" unless production_sql("eventstore_production", "SELECT count(*) FROM migrations").to_i.positive?
  production_sql("concurrent_development_mcp_production_cache", "SELECT count(*) FROM solid_cache_entries")
  production_sql("concurrent_development_mcp_production_queue", "SELECT count(*) FROM solid_queue_jobs")
end

Then("the five independent consumers are running after preparation") do
  rows = production_compose("ps", "--format", "json").lines.flat_map { |line| parsed = JSON.parse(line); parsed.is_a?(Array) ? parsed : [ parsed ] }
  ProductionDeploymentWorld::CONSUMERS.each do |name|
    raise "#{name} is not running" unless rows.any? { _1["Service"] == name && _1["State"] == "running" }
  end
end

Then("both published database ports are bound only to loopback") do
  configuration = JSON.parse(production_compose("config", "--format", "json"))
  %w[postgres pgbouncer].each do |name|
    raise "Non-loopback #{name} port" unless configuration.dig("services", name, "ports").all? { _1["host_ip"] == "127.0.0.1" }
  end
end

Then("production serves the React mount and its JavaScript and CSS") do
  page = production_http("/")
  raise "React mount is not served" unless page.code == "200" && page.body.include?("data-react-class")
  { "/ui/coordinator-ui.js" => "javascript", "/ui/coordinator-ui.css" => "text/css" }.each do |path, media_type|
    response = production_http(path)
    raise "Missing compiled asset #{path}" unless response.code == "200" && response.body.bytesize.positive? && response["Content-Type"].include?(media_type)
  end
end

Then("stable UI entry assets require revalidation") do
  %w[/ui/coordinator-ui.js /ui/coordinator-ui.css].each do |path|
    response = production_http(path)
    raise "Stale asset cache policy" unless response["Cache-Control"].include?("max-age=0") && response["Cache-Control"].include?("must-revalidate")
  end
end

Then("the production application image has no Node.js runtime") do
  production_compose("exec", "-T", "web", "/bin/sh", "-ec", 'test "$(id -u)" = 1000; ! command -v node; ! command -v npm')
end

Then("production MCP accepts Host {string}") do |host|
  result = production_rpc("tools/list", {}, host:)
  raise "MCP discovery unavailable for #{host}" unless result.fetch("tools").any?
end

Then("production MCP rejects Host {string}") do |host|
  response = production_rpc_response("tools/list", {}, host:)
  raise "Unexpected Host rejection: #{response.code} #{response.body}" unless response.code == "403" &&
    JSON.parse(response.body).dig("error", "message") == "Forbidden: Invalid Host header"
end

When("the production environment file is edited and normally deployed again") do
  production_write_settings("MCP_ALLOWED_HOSTS" => "mcp-next.example", "MCP_MAX_REQUEST_BYTES" => "131072")
  production_deploy
end

Then("every consumer has refreshed runtime settings without the removed setting") do
  ProductionDeploymentWorld::CONSUMERS.each do |name|
    # Inspect only test settings, never dump container credentials.
    script = 'require "json"; puts JSON.generate(ENV.to_h.slice("MCP_ALLOWED_HOSTS", "MCP_MAX_REQUEST_BYTES", "COORDINATOR_DEPLOYMENT_SAMPLE"))'
    settings = JSON.parse(production_compose("exec", "-T", name, "ruby", "-e", script))
    raise "Runtime settings not refreshed for #{name}: #{settings}" unless settings == {
      "MCP_ALLOWED_HOSTS" => "mcp-next.example", "MCP_MAX_REQUEST_BYTES" => "131072"
    }
  end
end

When("an agent stores UTF-8 documentation through production MCP") { production_capture_document }
Then("the asynchronous Task completes and its projected content becomes available") { production_document_available }

When("production is deployed again and its database containers are recreated") do
  production_document_available
  production_deploy
  production_compose("down", "--timeout", "60")
  production_deploy
end

Then("the same documentation and completed Task are still available") do
  production_document_available
  task = production_rpc("tasks/get", { taskId: @production_document_task_id }, name: @production_document_task_id)
  raise "Task state was lost" unless task["status"] == "completed" && task.dig("result", "structuredContent", "data", "artifact_id") == @production_artifact_id
end

Then("repeating the agent command returns the same documentation identity") do
  data, = production_command("development_artifact_capture", **@production_capture_arguments)
  raise "Command replay created a duplicate" unless data.fetch("artifact_id") == @production_artifact_id
end

When("an agent declares a work intention lasting thirty seconds through production MCP") { production_declare_short_intention }

Then("the real delayed job is scheduled in the queue database") do
  production_eventually("scheduled expiry job") do
    production_sql("concurrent_development_mcp_production_queue", "SELECT count(*) FROM solid_queue_scheduled_executions AS s JOIN solid_queue_jobs AS j ON j.id = s.job_id WHERE j.class_name = 'Coordinator::Processes::Jobs::ExpireWorkIntention'").to_i.positive?
  end
end

Then("the queue worker finishes it and records the bounded expiry fact") do
  production_eventually("finished expiry job") do
    production_sql("concurrent_development_mcp_production_queue", "SELECT count(*) FROM solid_queue_jobs WHERE class_name = 'Coordinator::Processes::Jobs::ExpireWorkIntention' AND finished_at IS NOT NULL").to_i.positive?
  end
  # Public, bounded event-store read only; never touch subscription internals.
  script = "events = PgEventstore.client.read(PgEventstore::Stream.all_stream, options: { max_count: 1, filter: { event_types: [{ type: 'ResourceWorkIntentionExpired', markers: ['work-intention:#{@production_intention_id}'] }] } }); abort 'expiry fact absent' unless events.one?"
  production_compose("exec", "-T", "web", "bundle", "exec", "rails", "runner", script)
end

When("deployment preparation is intentionally misconfigured") do
  production_document_available
  _, _, @production_failure_status = production_deploy(environment: { "CACHE_DATABASE_NAME" => "concurrent_development_mcp_production" }, allow_failure: true)
end

Then("deployment fails without restarting consumers") do
  raise "Misconfigured preparation unexpectedly succeeded" if @production_failure_status.success?
  running = production_compose("ps", "--services", "--status", "running").lines.map(&:strip)
  raise "Consumers restarted after failed preparation: #{running}" unless (running & ProductionDeploymentWorld::CONSUMERS).empty?
end

When("the valid production configuration is deployed again") { production_deploy }
