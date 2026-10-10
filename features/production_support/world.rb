# frozen_string_literal: true

require "json"
require "net/http"
require "open3"
require "securerandom"
require "tempfile"
require "tmpdir"
require "time"

# This profile deliberately does not load Rails, DatabaseCleaner, or the normal
# in-process subscription helpers. Every scenario owns a separate real cluster.
module ProductionDeploymentWorld
  ROOT = File.expand_path("../..", __dir__)
  CONSUMERS = %w[web subscription-process-managers subscription-task-results subscription-read-models jobs].freeze
  POSTGRES_IMAGE = "postgres:18@sha256:06cad38a5d9f5d24b4d83d86def30795d5e4b757fedbf5281172b576dedcd941"

  def production_setup
    @production_data = Dir.mktmpdir("production-acceptance-", File.join(ROOT, "tmp"))
    File.chmod(0o755, @production_data)
    @production_environment_file = Tempfile.new([ "production-acceptance-", ".env" ], File.join(ROOT, "tmp"))
    production_write_settings("MCP_ALLOWED_HOSTS" => "mcp-initial.example", "MCP_MAX_REQUEST_BYTES" => "65536",
                              "COORDINATOR_DEPLOYMENT_SAMPLE" => "initial")
    @production_project = "coordinator-acceptance-#{SecureRandom.hex(6)}"
    @production_environment = {
      "PRODUCTION_ENV_FILE" => @production_environment_file.path, "PRODUCTION_COMPOSE_PROJECT" => @production_project,
      "PG_HOST_DATA_DIR" => @production_data, "POSTGRES_USER" => "coordinator",
      "POSTGRES_PASSWORD" => SecureRandom.hex(32), "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "DATABASE_NAME" => "concurrent_development_mcp_production",
      "CACHE_DATABASE_NAME" => "concurrent_development_mcp_production_cache",
      "QUEUE_DATABASE_NAME" => "concurrent_development_mcp_production_queue",
      "PG_EVENTSTORE_DATABASE_NAME" => "eventstore_production",
      "POSTGRES_HOST_PORT" => "16435", "PGBOUNCER_HOST_PORT" => "16436", "MCP_HOST_PORT" => "18088",
      "COORDINATOR_IMAGE" => "concurrent-development-mcp:production-acceptance"
    }
    @production_request_sequence = 0
    @production_actor = { kind: "agent", id: @production_project }
    production_deploy
  end

  def production_run(*arguments, environment: {}, allow_failure: false)
    output, error, status = Open3.capture3(@production_environment.merge(environment), *arguments, chdir: ROOT)
    raise "Production command failed (#{status.exitstatus}): #{arguments.first}\n#{(output + error).lines.last(30).join}" unless status.success? || allow_failure

    [ output, error, status ]
  end

  def production_compose(*arguments)
    production_run("docker", "compose", "--env-file", @production_environment_file.path, "--project-name", @production_project,
                   "-f", "docker-compose.production.yml", *arguments).first
  end

  def production_deploy(environment: {}, allow_failure: false)
    production_run(File.join(ROOT, "bin/deploy-production"), environment:, allow_failure:)
  end

  def production_write_settings(settings)
    @production_environment_file.rewind
    @production_environment_file.truncate(0)
    @production_environment_file.write(settings.map { |key, value| "#{key}=#{value}\n" }.join)
    @production_environment_file.flush
  end

  def production_cleanup
    return unless @production_data

    production_compose("down", "--timeout", "60")
    # Remove only this scenario's freshly allocated fixture cluster, never any
    # caller-selected PG_HOST_DATA_DIR or the default production data directory.
    prefix = File.join(ROOT, "tmp", "production-acceptance-")
    raise "Unsafe production fixture cleanup" unless @production_data.start_with?(prefix) && File.realpath(@production_data) == @production_data

    production_run("docker", "run", "--rm", "--entrypoint", "/bin/sh", "--mount",
                   "type=bind,source=#{@production_data},target=/verification-data", POSTGRES_IMAGE,
                   "-ec", "find /verification-data -mindepth 1 -delete")
    Dir.rmdir(@production_data)
    @production_environment_file.close!
  end

  def production_eventually(label, timeout: 60)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      value = yield
      return value if value
      raise "Timed out waiting for #{label}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.25
    end
  end

  def production_http(path)
    Net::HTTP.start("127.0.0.1", 18088, open_timeout: 5, read_timeout: 15) { _1.get(path) }
  end

  def production_rpc_response(method, params, name: nil, host: nil)
    @production_request_sequence += 1
    request = Net::HTTP::Post.new("/mcp")
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json, text/event-stream"
    request["MCP-Protocol-Version"] = "2026-07-28"
    request["Mcp-Method"] = method
    request["Mcp-Name"] = name if name
    request["Host"] = host if host
    request.body = JSON.generate(jsonrpc: "2.0", id: @production_request_sequence, method:, params: params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities" => { extensions: { "io.modelcontextprotocol/tasks" => {} } },
        "io.modelcontextprotocol/clientInfo" => { name: "production-cucumber", version: "1.0" }
      }
    ))
    Net::HTTP.start("127.0.0.1", 18088, open_timeout: 5, read_timeout: 15) { _1.request(request) }
  end

  def production_rpc(method, params, name: nil, host: nil)
    response = production_rpc_response(method, params, name:, host:)
    raise "MCP HTTP #{response.code}: #{response.body}" unless response.code == "200"

    parsed = JSON.parse(response.body)
    raise "MCP error: #{parsed['error']}" if parsed["error"]

    parsed.fetch("result")
  end

  def production_tool(name, arguments)
    production_rpc("tools/call", { name:, arguments: }, name:).fetch("structuredContent")
  end

  def production_command(name, **arguments)
    response = production_rpc("tools/call", { name:, arguments:, task: { ttl: 600_000 } }, name:)
    task_id = response.fetch("taskId")
    terminal = production_eventually("#{name} Task #{task_id}") do
      task = production_rpc("tasks/get", { taskId: task_id }, name: task_id)
      task if %w[completed failed cancelled].include?(task["status"])
    end
    result = terminal.fetch("result")
    raise "#{name} Task failed: #{terminal}" unless terminal["status"] == "completed" && !result["isError"]

    [ result.fetch("structuredContent").fetch("data"), task_id ]
  end

  def production_capture_document
    @production_document = "Production documentation — preserve UTF-8 text without Base64."
    @production_capture_arguments = {
      command_id: "capture-production-document", actor: @production_actor,
      scope: "project:#{@production_project}", title: "Persistent production documentation", kind: "documentation", labels: [ "acceptance" ],
      content: { encoding: "utf-8", media_type: "text/plain", text: @production_document },
      source: { kind: "generated", locator: "mcp://#{@production_project}/documentation", revision: nil,
                observed_at: Time.now.utc.iso8601(6), collector: "production-cucumber" }
    }
    data, @production_document_task_id = production_command("development_artifact_capture", **@production_capture_arguments)
    @production_artifact_id = data.fetch("artifact_id")
  end

  def production_document_available
    production_eventually("projected documentation") do
      payload = production_tool("development_artifact_content_get", artifact_id: @production_artifact_id)
      payload if payload.dig("data", "content", "text") == @production_document
    end
  end

  def production_sql(database, sql)
    production_compose("exec", "-T", "-e", "PGPASSWORD=#{@production_environment.fetch('POSTGRES_PASSWORD')}", "pgbouncer",
                       "psql", "-h", "127.0.0.1", "-U", "coordinator", "-d", database, "-X", "-At", "-c", sql).strip
  end

  def production_declare_short_intention
    proposed_repository = SecureRandom.uuid_v7
    repository, = production_command("repository_register", command_id: "register-production-repository", actor: @production_actor,
                                     repository_id: proposed_repository, scope: "project:#{@production_project}", repository_key: "acceptance",
                                     display_name: "Production acceptance repository", paths: [], remotes: [])
    repository_id = repository.fetch("repository_id")
    common = { actor: @production_actor, change_set_id: "production-expiry", work_item_id: "production-expiry-work", attempt_id: "production-expiry-attempt" }
    production_command("change_set_create", command_id: "create-production-expiry", actor: @production_actor,
                       change_set_id: common[:change_set_id], goal: "Verify delayed production expiry", acceptance_criteria: [ "A real queue worker records expiry" ])
    production_command("work_item_create", command_id: "create-production-expiry-work", actor: @production_actor,
                       change_set_id: common[:change_set_id], work_item_id: common[:work_item_id], repository_id:,
                       goal: "Declare a bounded work intention", acceptance_criteria: [ "Expiry uses the dedicated queue" ])
    production_command("change_set_activate", command_id: "activate-production-expiry", actor: @production_actor, change_set_id: common[:change_set_id])
    production_eventually("ready coordination WorkItem") do
      context = production_tool("coord_context", change_set_id: common[:change_set_id])
      context.dig("data", "context", "work_items")&.any? { _1["work_item_id"] == common[:work_item_id] && _1["status"] == "ready" }
    end
    production_command("work_item_acquire", **common, command_id: "acquire-production-expiry", base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ])
    resource, = production_command("resource_resolve", command_id: "resolve-production-expiry-resource", actor: @production_actor, repository_id:, kind: "file", path: "README.md")
    intention, = production_command("work_intention_set_declare", **common, command_id: "declare-production-expiry", repository_id:,
                                    base_commit_oid: "a" * 40, resources: [ { resource_id: resource.fetch("resource_id"), mode: "shared",
                                    purpose: "Production queue acceptance", context: "A real delayed worker must record expiry" } ], ttl_seconds: 30)
    @production_intention_id = intention.fetch("intentions").first.fetch("intention_id")
  end
end

World(ProductionDeploymentWorld)

After("@production_deployment") do
  production_cleanup
end
