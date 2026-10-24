# frozen_string_literal: true

module Coordinator::Mcp
  module UsageSkills
    # An explicit operator client of public MCP tools, not a write-side service.
    # Reads supply context only; skill_publish rechecks authoritative revisions.
    class Installer
      REVISION_ATTEMPTS = 3
      ACTOR = { kind: "agent", id: "coordinator-usage-skill-installer" }.freeze

      def initialize(
        server:,
        definitions: Catalog.all,
        release: Catalog::RELEASE,
        run_id: SecureRandom.uuid_v7,
        output: $stdout,
        timeout_seconds: 60
      )
        @server = server
        @definitions = definitions
        @release = release
        @run_id = run_id
        @output = output
        @timeout_seconds = timeout_seconds
        @request_number = 0
      end

      def call
        @output.puts "Usage Skill installation run #{@run_id}; scope #{Catalog::SCOPE}"
        @definitions.map { install(_1) }
      end

      private

      def install(definition)
        REVISION_ATTEMPTS.times do |attempt|
          revision = observed_revision(definition)
          accepted = invoke("skill_publish", {
            command_id: "usage-skills:#{@release}:#{@run_id}:#{definition.name}:#{revision}",
            actor: ACTOR,
            name: definition.name,
            scope: Catalog::SCOPE,
            expected_revision: revision,
            description: definition.description,
            instructions: definition.instructions,
            assets: []
          })
          task_id = accepted.fetch("taskId")
          @output.puts "#{definition.name}: Task #{task_id}"
          @output.flush
          task = await_task(task_id)
          result = task.fetch("result")
          payload = result.fetch("structuredContent")
          unless result.fetch("isError")
            data = payload.fetch("data")
            installed = InstallationResult.new(
              name: definition.name, task_id:, revision: data.fetch("revision"), outcome: publication_outcome(payload)
            )
            @output.puts "#{installed.name}: #{installed.outcome} revision #{installed.revision}"
            return installed
          end

          code = payload.dig("data", "code")
          if code == "skill_revision_conflict" && attempt + 1 < REVISION_ATTEMPTS
            sleep 0.5
            next
          end

          raise InstallError.new(
            "#{definition.name}: #{code || payload.fetch('status')}; #{payload.fetch('summary')} Task #{task_id}. Partial progress is retained; retry with a new run after correcting terminal conflicts.",
            task_id:
          )
        end
      end

      def observed_revision(definition)
        payload = invoke("skill_get", { name: definition.name, scope: Catalog::SCOPE })
        case payload.fetch("status")
        when "ok" then payload.fetch("data").fetch("skill").fetch("revision")
        when "not_found" then 0
        else
          raise InstallError, "#{definition.name}: cannot read Skill context: #{payload.fetch('summary')}"
        end
      end

      def publication_outcome(payload)
        case payload.fetch("completion").fetch("effects")
        when "committed" then "published"
        when "unchanged" then "existing"
        else
          raise InstallError, "Skill publication has no definitive committed/unchanged outcome"
        end
      end

      def await_task(task_id)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout_seconds
        loop do
          task = invoke("task_get", { task_id: })
          case task.fetch("status")
          when "completed" then return task
          when "failed", "cancelled"
            raise InstallError.new("Task #{task_id}: #{task.fetch('statusMessage')}. Partial progress is retained.", task_id:)
          end
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            raise InstallError.new(
              "Task #{task_id} is still working. Nothing was cancelled or rolled back. Poll task_get, or resume this unchanged bundle with MCP_USAGE_SKILL_RUN_ID=#{@run_id}.",
              task_id:
            )
          end
          sleep task.fetch("pollIntervalMs") / 1_000.0
        end
      end

      def invoke(name, arguments)
        @request_number += 1
        response = JSON.parse(@server.handle_json(JSON.generate(
          jsonrpc: "2.0", id: @request_number, method: "tools/call",
          params: {
            name:, arguments:,
            _meta: {
              "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
              "io.modelcontextprotocol/clientCapabilities" => {},
              "io.modelcontextprotocol/clientInfo" => { name: "coordinator-usage-skill-installer", version: @release.to_s }
            }
          }
        )))
        if response["error"]
          raise InstallError, "#{name}: #{response.fetch('error').fetch('message')}"
        end
        result = response.fetch("result")
        if result["isError"]
          raise InstallError, "#{name}: #{JSON.generate(result.fetch('content'))}"
        end
        result.fetch("structuredContent")
      end
    end
  end
end
