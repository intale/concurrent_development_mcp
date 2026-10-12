# frozen_string_literal: true

# Load with Rails, not as application code. See the usage comment below.
# All writes use existing command operations. Only the three subscriptions under
# investigation run; public CLI managers have distinct diagnostic set names.
#
#   RAILS_ENV=test TEST_ENV_NUMBER=pgq_<unique_run> \
#   PG_QUERY_PROFILE_DIR="$PWD/tmp/pg_query_profile/<unique_run>" \
#   COORDINATOR_OBSERVABILITY_ENABLED=false \
#     bundle exec ruby -r ./spec/support/pg_eventstore_query_profile_safety.rb \
#       bin/rails runner script/pg_eventstore_query_profile.rb
#
# First create/migrate the matching Rails and pg_eventstore test databases using
# db:create/db:migrate and pg_eventstore:create/pg_eventstore:migrate. The event
# store URI must use development PgBouncer (localhost:6432), not a production URI.
# Optional: PG_QUERY_PROFILE_ITEMS=5 for a smoke run (real matrix defaults to 1000).
# PG_QUERY_PROFILE_MODE=analyse reruns analysis of an existing output directory.
# PG_QUERY_PROFILE_MODE=renewal-only and PG_QUERY_PROFILE_RENEWAL_TASK=<task_id>
# run the same persisted synthetic renewal without concurrent batch traffic; use
# a new output directory but the matrix's same dedicated test database suffix.
# SQL logs include synthetic fixture payloads; do not use this on real data.

module PgEventstoreQueryProfile
  ROOT = Rails.root.to_s
  SCRIPT = Rails.root.join("script", "pg_eventstore_query_profile.rb").to_s
  SAFETY = Rails.root.join("spec", "support", "pg_eventstore_query_profile_safety.rb").to_s
  THREAD_KEY = :pg_eventstore_query_profile_origin

  module_function

  def now
    Time.now.utc.iso8601(6)
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def output
    ENV.fetch("PG_QUERY_PROFILE_DIR")
  end

  def emit(io, kind, **attributes)
    io.puts(JSON.generate(attributes.merge(time: now, monotonic: monotonic, pid: Process.pid, kind:)))
    io.flush
  end

  def tagged(origin)
    previous = Thread.current[THREAD_KEY]
    Thread.current[THREAD_KEY] = origin
    yield
  ensure
    Thread.current[THREAD_KEY] = previous
  end

  def setup_logger(role)
    logger = Logger.new(File.join(output, "#{role}.sql.jsonl"))
    logger.level = :debug
    logger.formatter = lambda do |severity, time, _program, message|
      JSON.generate(
        time: time.utc.iso8601(6), monotonic: monotonic, role:, pid: Process.pid,
        thread: Thread.current.object_id, severity:,
        origin: Thread.current[THREAD_KEY] || { kind: "subscription-background" },
        sql: message.to_s
      ) + "\n"
    end
    PgEventstore.logger = logger
  end

  def registration(role)
    container = Coordinator::Container
    case role
    when "lane0", "lane1"
      container["subscriptions.coordination_task_executors"].fetch(Integer(role.delete_prefix("lane")))
    when "batch"
      container["subscriptions.operation_batch_runner"]
    else
      raise "Unknown consumer role #{role.inspect}"
    end
  end

  def consumer
    role = ENV.fetch("PG_QUERY_PROFILE_ROLE")
    setup_logger(role)
    registration = registration(role)
    events = File.open(File.join(output, "#{role}.handlers.jsonl"), "a")
    invocation = 0
    handler = lambda do |event|
      invocation += 1
      origin = {
        kind: "handler", subscription: registration.definition.subscription_name,
        invocation:, event_id: event.id, event_type: event.type,
        tool: event.data["tool_name"], batch_id: event.data["batch_id"],
        task_id: event.data["task_id"]
      }
      start = monotonic
      tagged(origin) do
        emit(events, "handler-start", **origin)
        begin
          registration.handler.call(event)
          emit(events, "handler-end", **origin, elapsed: monotonic - start)
        rescue StandardError => error
          emit(events, "handler-error", **origin, elapsed: monotonic - start,
               error_class: error.class.name, message: error.message)
          raise
        end
      end
    end
    manager = PgEventstore.subscriptions_manager(
      subscription_set: "pg-query-profile-#{ENV.fetch('TEST_ENV_NUMBER')}-#{role}"
    )
    manager.subscribe(registration.definition.subscription_name, handler:,
                      options: registration.definition.options, pull_interval: 1.0)
    manager.start!
    File.write(File.join(output, "#{role}.ready.json"), JSON.generate(pid: Process.pid, time: now))
  end

  # Public, read-only PostgreSQL inspection. Backend PIDs identify observations,
  # never application identities. No session settings or session locks are used.
  def observe
    connection = direct_connection
    samples = File.open(File.join(output, "locks.jsonl"), "a")
    until File.exist?(File.join(output, "observer.stop"))
      start = monotonic
      connection.exec("BEGIN READ ONLY")
      connection.exec("SET LOCAL statement_timeout = '1500ms'")
      activity = connection.exec(<<~SQL).to_a
        SELECT pid, application_name, backend_xid, backend_xmin, state,
               wait_event_type, wait_event, xact_start, query_start,
               pg_blocking_pids(pid) AS blocking_pids, left(query, 2000) AS query
        FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid()
      SQL
      locks = connection.exec(<<~SQL).to_a
        SELECT l.pid, l.locktype, l.mode, l.granted, l.page, l.tuple,
               l.transactionid, l.virtualxid, c.relname AS relation
        FROM pg_locks l
        LEFT JOIN pg_class c ON c.oid = l.relation
        WHERE l.pid IN (
          SELECT pid FROM pg_stat_activity
          WHERE datname = current_database() AND pid <> pg_backend_pid()
        )
      SQL
      stats = connection.exec(<<~SQL).to_a.first
        SELECT xact_commit, xact_rollback, deadlocks, temp_bytes
        FROM pg_stat_database WHERE datname = current_database()
      SQL
      connection.exec("COMMIT")
      emit(samples, "lock-sample", activity:, locks:, stats:, elapsed: monotonic - start)
      sleep(0.25)
    end
  ensure
    connection&.close
    samples&.close
  end

  def direct_connection
    uri = URI.parse(PgEventstore.config.pg_uri)
    credentials = PG::Connection.conninfo_parse(ENV.fetch("PG_EVENTSTORE_URI"))
                    .to_h { [ _1.fetch(:keyword), _1[:val] ] }
    PG.connect(host: uri.host, port: Integer(ENV.fetch("PG_QUERY_PROFILE_DIRECT_PORT", "5532")),
               dbname: uri.path.delete_prefix("/"),
               user: credentials.fetch("user"), password: credentials.fetch("password"))
  end

  class Workload
    def initialize
      @container = Coordinator::Container
      @events = File.open(File.join(PgEventstoreQueryProfile.output, "controller.jsonl"), "a")
      @phases = []
      @children = []
      @actor = { kind: "agent", id: "query-profile" }
      @items = Integer(ENV.fetch("PG_QUERY_PROFILE_ITEMS", "1000"))
      raise "items must be between 1 and 1000" unless (1..1000).cover?(@items)

      @timeout = Integer(ENV.fetch("PG_QUERY_PROFILE_TIMEOUT", "480"))
    end

    def run
      PgEventstoreQueryProfile.setup_logger("producer")
      start_children
      phase("idle") { sleep(5) }
      first = phase("capture-single-first") { batches([ capture_batch("first") ]) }
      phase("capture-single-warm") { batches([ capture_batch("warm") ]) }
      @source_ids = first.fetch(0).fetch(:artifact_ids)
      seed_other_fixtures
      phase("relation-single-independent-sources") { batches([ relation_batch("independent") ]) }
      phase("capture-concurrent-and-cold-renewal") do
        batches(4.times.map { capture_batch("parallel-#{_1}") }, renewal: "cold")
      end
      phase("relation-concurrent-shared-sources-and-warm-renewal") do
        batches(2.times.map { relation_batch("shared-#{_1}", shared: true) }, renewal: "warm")
      end
      File.write(File.join(PgEventstoreQueryProfile.output, "complete.json"), JSON.pretty_generate(phases: @phases))
    rescue StandardError => error
      PgEventstoreQueryProfile.emit(@events, "controller-error", error_class: error.class.name, message: error.message,
                                   backtrace: error.backtrace.first(12))
      raise
    ensure
      stop_children
      @events.close
      PgEventstoreQueryProfile.analyse
    end

    def run_renewal
      PgEventstoreQueryProfile.setup_logger("producer")
      prior = PgEventstoreQueryProfile.tagged(kind: "fixture") do
        @container["tasks.loader"].call(ENV.fetch("PG_QUERY_PROFILE_RENEWAL_TASK")).state
      end
      raise "Expected a synthetic renewal Task" unless prior.tool_name == "work_intention_set_renew" &&
        prior.command_input.input.actor.actor_id == @actor.fetch(:id)

      @renewal_input = prior.command_input.input.to_h.except(:actor, :ttl_seconds)
      start_children
      phase("renewal-only-warm") { batches([], renewal: "warm") }
      File.write(File.join(PgEventstoreQueryProfile.output, "complete.json"), JSON.pretty_generate(phases: @phases))
    ensure
      stop_children
      @events.close
      PgEventstoreQueryProfile.analyse
    end

    def phase(name)
      phase = { name:, start: PgEventstoreQueryProfile.now, start_monotonic: PgEventstoreQueryProfile.monotonic }
      @phases << phase
      PgEventstoreQueryProfile.emit(@events, "phase-start", phase: name)
      puts "START #{name}"
      $stdout.flush
      yield.tap { phase[:ok] = true }
    ensure
      phase[:finish] = PgEventstoreQueryProfile.now
      phase[:elapsed] = PgEventstoreQueryProfile.monotonic - phase.fetch(:start_monotonic)
      File.write(File.join(PgEventstoreQueryProfile.output, "phases.json"), JSON.pretty_generate(@phases))
      PgEventstoreQueryProfile.emit(@events, "phase-end", **phase)
      puts "END #{name} #{phase[:elapsed].round(3)}s"
      $stdout.flush
    end

    def execute(name, attributes = {})
      PgEventstoreQueryProfile.tagged(kind: "fixture", operation: name) do
        unwrap(@container["operations.#{name}"].call(common(name).merge(attributes)))
      end
    end

    def common(label)
      { command_id: "profile-#{label}-#{SecureRandom.uuid_v7}", actor: @actor }
    end

    def unwrap(result)
      raise "Command failed: #{result.failure.inspect}" if result.failure?

      result.value!
    end

    def artifact_input(label)
      common(label).merge(
        scope: "query-profile:#{ENV.fetch('TEST_ENV_NUMBER')}", title: "Synthetic #{label}", kind: "documentation",
        labels: [ "query-profile" ],
        content: { encoding: "utf-8", media_type: "text/plain", text: "Generated diagnostic fixture #{label}\n" },
        source: { kind: "generated", locator: "profile://#{label}", revision: nil,
                 observed_at: PgEventstoreQueryProfile.now, collector: "query-profile" }
      )
    end

    def capture_batch(label)
      input = common(label).merge(batch_id: SecureRandom.uuid_v7,
                                  items: @items.times.map { artifact_input("#{label}-#{_1}") })
      command = unwrap(@container["operations.prepare_create_development_artifact_capture_batch"].call(input))
      { label:, command:, batch_id: input.fetch(:batch_id),
       artifact_ids: command.items.map { _1.command_input.input.artifact.artifact_id } }
    end

    def relation_batch(label, shared: false)
      items = @items.times.map do |index|
        common("#{label}-#{index}").merge(
          source_artifact_id: shared ? @shared_sources.fetch(index % @shared_sources.length) : @source_ids.fetch(index),
          relation: "references",
          target: { kind: "artifact", id: shared ? @source_ids.fetch(index) : @target_id },
          attributes: { path: "#{label}/item-#{index}.md" }
        )
      end
      input = common(label).merge(batch_id: SecureRandom.uuid_v7, items:)
      command = unwrap(@container["operations.prepare_create_development_artifact_relation_declare_batch"].call(input))
      { label:, command:, batch_id: input.fetch(:batch_id) }
    end

    def batches(specifications, renewal: nil)
      # Multiple producers use real separate connections. All consumers are
      # already running while each producer submits a complete batch atomically.
      producer_threads = specifications.map do |specification|
        Thread.new do
          PgEventstoreQueryProfile.tagged(kind: "producer", batch_id: specification.fetch(:batch_id)) do
            task = unwrap(@container["operations.submit_coordination_task"].call(specification.fetch(:command)))
            specification.merge(task_id: task.task_id)
          end
        end
      end
      submitted = producer_threads.map(&:value)
      renewal_task = if renewal
        # Let bulk acceptance and the first page begin before issuing renewal.
        sleep(0.25)
        PgEventstoreQueryProfile.tagged(kind: "producer", operation: "renewal") do
          unwrap(@container["operations.submit_renew_work_intention_set_task"].call(
            common("renew-#{renewal}").merge(@renewal_input, ttl_seconds: renewal == "cold" ? 2400 : 3600)
          )).task_id
        end
      end
      await(submitted, renewal_task:)
      submitted.each { _1.delete(:command) }
      PgEventstoreQueryProfile.emit(@events, "workload-result", batches: submitted, renewal_task:)
      submitted
    end

    def await(submitted, renewal_task:)
      deadline = PgEventstoreQueryProfile.monotonic + @timeout
      loop do
        check_children!
        status = PgEventstoreQueryProfile.tagged(kind: "diagnostic-progress-read") do
          submitted.map do |specification|
            task = @container["tasks.loader"].call(specification.fetch(:task_id)).state
            batch = @container["operation_batches.loader"].call(specification.fetch(:batch_id)).state
            raise "Task failed: #{task.to_h.inspect}" if [ "failed", "cancelled" ].include?(task.status)
            { label: specification.fetch(:label), task: task.status, terminal: !batch.terminal.nil?,
             succeeded: batch.succeeded_count, rejected: batch.rejected_count }
          end
        end
        renewal = if renewal_task
          PgEventstoreQueryProfile.tagged(kind: "diagnostic-progress-read") do
            @container["tasks.loader"].call(renewal_task).state
          end
        end
        raise "Renewal failed: #{renewal.to_h.inspect}" if renewal && [ "failed", "cancelled" ].include?(renewal.status)
        PgEventstoreQueryProfile.emit(@events, "progress", batches: status, renewal_status: renewal&.status)
        if status.all? { _1.fetch(:terminal) && _1.fetch(:task) == "completed" } && (!renewal || renewal.terminal?)
          raise "Unexpected item rejection: #{status.inspect}" if status.any? { _1.fetch(:rejected).positive? }
          return
        end
        raise "Workload timed out after #{@timeout}s: #{status.inspect}" if PgEventstoreQueryProfile.monotonic >= deadline

        sleep(1)
      end
    end

    def seed_other_fixtures
      @target_id = execute("execute_capture_development_artifact", artifact_input("relation-target")).data.artifact_id
      @shared_sources = 16.times.map do |index|
        execute("execute_capture_development_artifact", artifact_input("shared-source-#{index}")).data.artifact_id
      end
      repository_id = SecureRandom.uuid_v7
      change_set_id = "profile-change-set"
      work_item_id = "profile-work-item"
      attempt_id = "profile-attempt"
      execute("execute_register_repository", repository_id:, scope: "profile", repository_key: "profile",
              paths: [], remotes: [])
      execute("execute_create_change_set", change_set_id:, goal: "Synthetic profiling prerequisites",
              acceptance_criteria: [ "Only generated data is used" ])
      execute("execute_create_work_item", change_set_id:, work_item_id:, repository_id:, goal: "Profile renewal",
              acceptance_criteria: [ "Renewal remains correct during a concurrent import" ])
      activation = execute("execute_activate_change_set", change_set_id:)
      @container["process_managers.change_set_readiness"].call(activation.terminal_event)
      base_commit = ENV.fetch("PG_QUERY_PROFILE_BASE_COMMIT")
      execute("execute_acquire_work_item", change_set_id:, work_item_id:, attempt_id:,
              base_snapshots: [ { repository_id:, commit_oid: base_commit } ])
      resources = 21.times.map do |index|
        resource = execute("execute_resolve_resource", repository_id:, kind: "file", path: "profile/item-#{index}.txt")
        { resource_id: resource.data.resource_id, mode: "shared", purpose: "Synthetic profiling fixture", context: "No real files are changed" }
      end
      declaration = execute("execute_declare_work_intention_set", change_set_id:, work_item_id:, attempt_id:, repository_id:,
                            base_commit_oid: base_commit, resources:, ttl_seconds: 1800).data
      @renewal_input = { change_set_id:, work_item_id:, attempt_id:, intention_set_id: declaration.intention_set_id,
                        intentions: declaration.intentions.map { _1.to_h.slice(:resource_id, :intention_id, :fencing_token) } }
    end

    def spawn_child(role, arguments)
      env = { "PG_QUERY_PROFILE_MODE" => role == "observer" ? "observer" : "consumer",
             "PG_QUERY_PROFILE_ROLE" => role, "COORDINATOR_OBSERVABILITY_ENABLED" => "false" }
      log = File.open(File.join(PgEventstoreQueryProfile.output, "#{role}.stdout.log"), "a")
      pid = Process.spawn(env, "bundle", "exec", *arguments, chdir: ROOT, out: log, err: log)
      log.close
      @children << { role:, pid: }
    end

    def start_children
      %w[lane0 lane1 batch].each do |role|
        spawn_child(role, [ "pg-eventstore", "subscriptions", "start", "-p", File.join(PgEventstoreQueryProfile.output, "#{role}.pid"),
                           "-r", "./config/environment.rb", "-r", SAFETY, "-r", SCRIPT ])
      end
      spawn_child("observer", [ "ruby", "-r", SAFETY, "bin/rails", "runner", SCRIPT ])
      deadline = PgEventstoreQueryProfile.monotonic + 60
      until %w[lane0 lane1 batch].all? { File.exist?(File.join(PgEventstoreQueryProfile.output, "#{_1}.ready.json")) }
        check_children!
        raise "Consumer startup timed out" if PgEventstoreQueryProfile.monotonic > deadline

        sleep(0.25)
      end
    end

    def check_children!
      @children.reject { _1[:reaped] }.each do |child|
        result = Process.waitpid2(child.fetch(:pid), Process::WNOHANG)
        next unless result

        child[:reaped] = true
        raise "Diagnostic #{child.fetch(:role)} exited: #{result.last} (see its stdout log)"
      end
    end

    def stop_children
      File.write(File.join(PgEventstoreQueryProfile.output, "observer.stop"), "stop\n")
      @children.reject { _1[:reaped] || _1.fetch(:role) == "observer" }.each do |child|
        Process.kill("TERM", child.fetch(:pid))
      rescue Errno::ESRCH
        nil
      end
      deadline = PgEventstoreQueryProfile.monotonic + 30
      loop do
        @children.reject { _1[:reaped] }.each do |child|
          child[:reaped] = true if Process.waitpid(child.fetch(:pid), Process::WNOHANG)
        rescue Errno::ECHILD
          child[:reaped] = true
        end
        break if @children.all? { _1[:reaped] } || PgEventstoreQueryProfile.monotonic >= deadline

        sleep(0.25)
      end
      alive = @children.reject { _1[:reaped] }
      warn "Diagnostic children still stopping: #{alive.inspect}" unless alive.empty?
    end
  end

  def shape(sql)
    sql.gsub(/'(?:[^']|'')*'/m, "?").gsub(/\b\d+(?:\.\d+)?\b/, "?").gsub(/\s+/, " ").strip
  end

  def sql_statement?(message)
    /\A\s*(SELECT|INSERT|UPDATE|DELETE|WITH|BEGIN|COMMIT|ROLLBACK|SET|CREATE|ALTER|DROP|LOCK|ANALYZE|VACUUM|EXPLAIN|TRUNCATE|SAVEPOINT|RELEASE)\b/i.match?(message)
  end

  def records(path)
    return unless File.exist?(path)

    File.foreach(path) do |line|
      next if line.start_with?("#") || !line.end_with?("\n")

      yield JSON.parse(line)
    end
  end

  # Query plans are collected only after the workload. EXPLAIN without ANALYZE
  # plans the captured reads but does not execute them or change planner settings.
  def plans
    queries = {}
    %w[lane0 lane1 batch].each do |role|
      records(File.join(output, "#{role}.sql.jsonl")) do |record|
        sql = record.fetch("sql")
        next unless record.dig("origin", "kind") == "handler" && /\A\s*SELECT\b/i.match?(sql)
        next if /pg_try_|pg_advisory_|set_config|FOR UPDATE/i.match?(sql)

        queries[shape(sql)] ||= { role:, origin: record.fetch("origin"), sql: }
      end
    end
    connection = direct_connection
    connection.exec("BEGIN READ ONLY")
    connection.exec("SET LOCAL statement_timeout = '2000ms'")
    result = queries.values.map do |query|
      plan = connection.exec("EXPLAIN (FORMAT JSON) #{query.fetch(:sql)}").first.fetch("QUERY PLAN")
      query.merge(plan: JSON.parse(plan))
    end
    connection.exec("COMMIT")
    File.write(File.join(output, "query_plans.json"), JSON.pretty_generate(result))
    puts "Captured #{result.length} read-only query plans"
  ensure
    connection&.close
  end

  def analyse
    phase_file = File.join(output, "phases.json")
    return unless File.exist?(phase_file)

    phases = JSON.parse(File.read(phase_file))
    results = phases.to_h { [ _1.fetch("name"), { elapsed: _1.fetch("elapsed"), roles: {} } ] }
    %w[lane0 lane1 batch producer].each do |role|
      path = File.join(output, "#{role}.sql.jsonl")
      next unless File.exist?(path)

      records(path) do |record|
        phase = phases.find { record.fetch("time") >= _1.fetch("start") && record.fetch("time") <= _1.fetch("finish") }
        next unless phase

        origin = record.fetch("origin").fetch("kind")
        counts = (results.fetch(phase.fetch("name"))[:roles][role] ||= {})
        group = (counts[origin] ||= {
          queries: 0, bytes: 0, verbs: Hash.new(0), shapes: Hash.new(0), non_sql_messages: Hash.new(0)
        })
        unless sql_statement?(record.fetch("sql"))
          group[:non_sql_messages][record.fetch("sql")] += 1
          next
        end

        group[:queries] += 1
        group[:bytes] += record.fetch("sql").bytesize
        group[:verbs][record.fetch("sql").lstrip.split(/\s+/, 2).first.to_s.upcase] += 1
        group[:shapes][shape(record.fetch("sql"))] += 1
        if origin == "handler"
          invocation = (counts[:invocations] ||= {})
          detail = (invocation[record.fetch("origin").fetch("invocation")] ||= {
            event_type: record.fetch("origin")["event_type"], tool: record.fetch("origin")["tool"],
            queries: 0, verbs: Hash.new(0)
          })
          detail[:queries] += 1
          detail[:verbs][record.fetch("sql").lstrip.split(/\s+/, 2).first.to_s.upcase] += 1
        end
      end
    end
    %w[lane0 lane1 batch].each do |role|
      path = File.join(output, "#{role}.handlers.jsonl")
      next unless File.exist?(path)

      records(path) do |record|
        next unless [ "handler-end", "handler-error" ].include?(record.fetch("kind"))

        phase = phases.find { record.fetch("time") >= _1.fetch("start") && record.fetch("time") <= _1.fetch("finish") }
        next unless phase

        counts = (results.fetch(phase.fetch("name"))[:roles][role] ||= {})
        (counts[:handlers] ||= []) << record.slice("invocation", "event_type", "tool", "elapsed", "kind", "error_class")
      end
    end
    records(File.join(output, "locks.jsonl")) do |record|
      phase = phases.find { record.fetch("time") >= _1.fetch("start") && record.fetch("time") <= _1.fetch("finish") }
      next unless phase

      result = results.fetch(phase.fetch("name"))
      observed = (result[:locks] ||= {
        samples: 0, predicate_locks: Hash.new(0), waiting_locks: Hash.new(0), waits: Hash.new(0), examples: [],
        predicate_page_overlap: Hash.new(0), overlap_examples: [],
        stats_first: record.fetch("stats"), stats_last: nil
      })
      observed[:samples] += 1
      observed[:stats_last] = record.fetch("stats")
      record.fetch("locks").each do |lock|
        key = "#{lock.fetch('locktype')}:#{lock.fetch('relation') || lock['transactionid'] || lock['virtualxid']}"
        observed[:predicate_locks][key] += 1 if lock.fetch("mode") == "SIReadLock"
        observed[:waiting_locks]["#{lock.fetch('mode')}:#{key}"] += 1 if lock.fetch("granted") == "f"
      end
      pages = record.fetch("locks").select { _1.fetch("mode") == "SIReadLock" && _1.fetch("locktype") == "page" }
      pages.group_by { [ _1.fetch("relation"), _1.fetch("page") ] }.each do |(relation, page), locks|
        pids = locks.map { _1.fetch("pid") }.uniq
        next unless pids.length > 1

        observed[:predicate_page_overlap][relation] += 1
        if observed[:overlap_examples].length < 20
          observed[:overlap_examples] << { time: record.fetch("time"), relation:, page:, pids: }
        end
      end
      record.fetch("activity").each do |activity|
        next unless activity.fetch("wait_event_type") == "Lock" || activity.fetch("blocking_pids") != "{}"

        key = "#{activity.fetch('wait_event_type')}:#{activity.fetch('wait_event')}"
        observed[:waits][key] += 1
        if observed[:examples].length < 20 && !observed[:examples].any? { _1.fetch("query") == activity.fetch("query") }
          observed[:examples] << activity
        end
      end
    end
    results.each_value do |result|
      next unless result[:locks]

      locks = result[:locks]
      locks[:stats_delta] = locks.fetch(:stats_last).to_h do |name, value|
        [ name, Integer(value) - Integer(locks.fetch(:stats_first).fetch(name)) ]
      end
    end
    File.write(File.join(output, "summary.json"), JSON.pretty_generate(results))
    puts "Diagnostic summary: #{File.join(output, 'summary.json')}"
  end

  def run
    # The safety guard is under spec/support; Rails runner loads it explicitly
    # because this diagnostic deliberately does not boot RSpec or Cucumber.
    PgEventstoreQueryProfileSafety.verify!
    mode = ENV.fetch("PG_QUERY_PROFILE_MODE", "controller")
    if [ "controller", "renewal-only" ].include?(mode) && Dir.exist?(output) && !Dir.empty?(output)
      raise "Use a fresh output directory; existing diagnostic logs must not be overwritten or mixed"
    end
    FileUtils.mkdir_p(output)
    case mode
    when "consumer" then consumer
    when "observer" then observe
    when "analyse" then analyse
    when "controller" then Workload.new.run
    when "renewal-only" then Workload.new.run_renewal
    when "plans" then plans
    else raise "Unknown query profile mode"
    end
  end
end

PgEventstoreQueryProfile.run
