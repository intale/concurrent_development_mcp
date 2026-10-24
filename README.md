# MCP server for concurrent development

This project enables distributed AI agents to coordinate their work. It does not spawn or orchestrate agents; instead,
it provides functions for recording work that agents plan, start, and finish. It also acts as a repository for
development artifacts such as AI skills, user decisions, documentation, URLs, and other assets produced during
development. Checkpointed development state makes work resumable.

You can import existing AI-related assets and build state, then rely on this MCP server throughout agentic development.
Because the application persists its state in PostgreSQL, it can run in a shared environment and coordinate work across
multiple agents, projects, and locations.

**Attention!** This tool was prompted using AI agent, so treat it accordingly.

**Attention!** The implementation is under development right now. No promises of compatibility between commits.

## Usage

### MCP clients and asynchronous commands

Clients do not need to advertise the Tasks extension to use this server. Discover
the available tools and server capabilities normally. Read tools return the
latest available projections; mutations always return durable asynchronous Task
handles, including for clients that have not declared Tasks support.

Ordinary clients receive a standard MCP tool result (`content` and
`structuredContent`), with the Task handle in `structuredContent.taskId`.
Persist it and call the discoverable `task_get` tool with `{ "task_id": "..." }`
at `pollIntervalMs` until terminal. Use `task_cancel` for cooperative cancellation;
its acknowledgement does not establish cancellation or roll back effects.
Initial acceptance confirms submission, not command completion.
Inspect the terminal result's `isError` and `structuredContent.completion` for
the outcome and committed effects. Successful completion does not require an
entity read-back, and projections may still lag. Only modern clients explicitly
advertising `io.modelcontextprotocol/tasks` receive extension-native
`CreateTaskResult` responses. They may use `tasks/get`, `tasks/update`, and
`tasks/cancel`; these protocol methods remain available without an admission gate.
The supported MCP protocol, envelope, transport and host checks still apply;
there is no synchronous mutation fallback.

### MCP usage Skills

Product usage guides are ordinary versioned Skills in exact scope
`mcp:concurrent-development-coordinator`. Start with:

```json
{"name":"coordinator-getting-started","scope":"mcp:concurrent-development-coordinator"}
```

Pass that input to `skill_get`. The entry guide routes to focused Skills for
development coordination, knowledge/imports, literal search, decisions/guidance,
and integration/releases. `skill_list` in that scope discovers their descriptions.
Project-specific development rules are separate Skills; no scope precedence is inferred.

After starting Rails and its coordinator subscriptions, explicitly install or
update the bundled guides in the current Rails environment:

```sh
bin/install-mcp-skills
```

For a production container, the corresponding explicit operator command is:

```sh
docker compose --env-file .env.production --project-name concurrent-development-mcp-production -f docker-compose.production.yml exec web bin/install-mcp-skills
```

Nothing publishes automatically during startup/deployment. The command uses the
public MCP JSON-RPC tools, not direct event-store or read-model writes. It manages
only the six named product Skills in the exact product scope. Matching snapshots
are authoritative no-ops; changed snapshots become new immutable revisions using
optimistic expected revisions. Other Skills/scopes are untouched. Run the updater
after an application update that changes the bundled guides.
`MCP_USAGE_SKILL_TIMEOUT_SECONDS` controls the per-Task wait (default 60 seconds,
range 0..3600); reaching it reports a pending handle without cancelling work.

The command prints its run UUID and each durable Task handle before polling.
Timeout/failure retains partial progress and never cancels or rolls it back.
Poll `task_get` using a printed handle. For an interrupted request, the same bundle
and observed revision can recover the same Task with
`MCP_USAGE_SKILL_RUN_ID=<printed-uuid> bin/install-mcp-skills`; an advanced projection
may instead lead to an authoritative no-op. A fresh reconciliation or corrected
intent uses a new run UUID (omit the variable). Repeated unresolved revision
conflicts stop after bounded attempts; refresh context before another run.

`skill_get`/`skill_list` remain eventually consistent read-model queries. Publication
success does not wait for projection freshness; there is no static fallback and
missing/lagging documentation never prevents other MCP tools from serving requests.

### Environment setup

Steps to set up the development environment:

- start docker compose first via `docker compose up`
- run `./bin/setup_db` to create rails and pg_eventstore databases if this is your initial run
- run `rails s` to start rails server
- run
  `bundle exec pg-eventstore subscriptions start -r ./config/environment.rb -r ./config/pg_eventstore_subscriptions.rb`
  to start pg_eventstore subscriptions

Development Compose sets PostgreSQL `max_pred_locks_per_transaction=256` so the
default 15 parallel event-store test runners have room in the shared SSI lock
arena. Updating this setting recreates only the development PostgreSQL container;
its bind-mounted data remains intact. Production Compose is configured separately.

### Production with Docker Compose

Requirements: Docker Engine with Compose v2 (including `up --wait`) and Bash.
The production setup is separate from development/test Compose and runs Rails,
the standalone compiled React UI, three subscription processes, and a dedicated
Solid Queue worker. There is no Node.js server in production.

1. Copy `config/production.env.example` to `.env.production` and set
   `POSTGRES_PASSWORD`, `SECRET_KEY_BASE`, and `GRAFANA_ADMIN_PASSWORD` to independent random secrets.
   For example, `openssl rand -hex 32` generates a database password and
   `openssl rand -hex 64` generates a Rails secret. Keep this ignored file private
   (`chmod 600 .env.production`). Compose reads it directly; dotenv is not required.
2. Set `PG_HOST_DATA_DIR` to the PostgreSQL host data directory. Its default is
   `./data`, relative to this project, not a Docker-managed volume. For an existing
   directory, make its root traversable by PostgreSQL (for example, mode `0755`);
   the image manages private PostgreSQL-owned files under `18/docker`. Do not use
   an unrelated directory or reuse the development cluster. Bind-directory
   ownership can require host administrator assistance, particularly with
   rootless Docker. Do not recursively change permissions on database files.
3. Run `bin/deploy-production` from the checkout. For a different environment
   file or Compose project, set `PRODUCTION_ENV_FILE` and
   `PRODUCTION_COMPOSE_PROJECT` when running the executable.

For MCP requests using a non-loopback hostname, set `MCP_ALLOWED_HOSTS` in the
production environment file, for example:

```dotenv
MCP_ALLOWED_HOSTS=mcp.example.com,api.example.com:8088
```

Entries are comma-separated additional allowed `Host` values. A bare hostname
allows any port; `hostname:port` allows that exact value. Do not include a URL
scheme or path. Matching is case-insensitive, and the default loopback hosts
(`localhost`, `127.0.0.1`, and `::1`) remain allowed. An unset or blank value keeps
the loopback-only default.

Every application service, including preparation and subscription workers, loads
the selected environment file through Compose's `env_file`. Run
`bin/deploy-production` after changing `.env.production`: it rereads that file
and recreates the consumers, applying added, changed, and removed runtime settings
without another manual step. `docker compose restart` alone does not reload
container environments. Explicit Compose settings enforce production mode and
internal PgBouncer routing; shell overrides still take precedence for interpolated
settings such as database names and published ports. For direct Compose commands
using a custom file, set `PRODUCTION_ENV_FILE` to that same file as well as
passing `--env-file`.

The script builds the image and assets, starts healthy PostgreSQL/PgBouncer,
stops existing consumers, creates missing databases and applies pending
migrations, then recreates consumers from the same image. Run it again after
updating the checkout. Preparation runs afresh on every deploy; failures leave
consumers stopped and existing data intact. A brief outage is expected. Do not
run separate migration processes alongside deployment.

Four separate databases are retained: Rails/MCP primary, pg_eventstore,
Solid Cache, and Solid Queue. Names are configurable in the environment file;
they must be distinct lowercase SQL identifiers of at most 63 characters, not
maintenance database names. No unused Action Cable database is provisioned.
Both runtime and preparation connect through transaction-mode PgBouncer.
Changing initial PostgreSQL credentials in the environment file does not rotate
credentials in an existing cluster; handle password changes explicitly.

| Service | Host address |
| --- | --- |
| UI | `http://127.0.0.1:8088/` |
| MCP | `http://127.0.0.1:8088/mcp` |
| Event-store administration | `http://127.0.0.1:8088/eventstore` |
| Grafana administration and dashboards | `http://127.0.0.1:8089/` |
| PostgreSQL | `127.0.0.1:6435` |
| PgBouncer | `127.0.0.1:6436` |

All ports bind to loopback. The application and administration UI have no
authentication in this scope; do not publish them remotely. This deployment
does not supply TLS, backups, or automatic PostgreSQL major-version upgrades.
Persistent host storage survives container removal, but is not a backup.

Read-only inspection and shutdown (use the same project name if overridden):

```sh
docker compose --env-file .env.production -f docker-compose.production.yml ps --all
docker compose --env-file .env.production -f docker-compose.production.yml logs --tail 100 web
docker compose --env-file .env.production -f docker-compose.production.yml logs --tail 100 subscription-process-managers subscription-task-results subscription-read-models jobs
curl --fail http://127.0.0.1:8088/up
docker compose --env-file .env.production -f docker-compose.production.yml down
```

`/up` reports Rails liveness, not projection freshness or subscription progress.
Use the existing event-store administration UI to inspect subscriptions. Each
subscription set is owned by one CLI process; do not scale duplicate consumers
of the same set. Stop/recreate consumers through Compose, which sends SIGTERM;
do not change their internal lifecycle state.

An atomic marker under `tmp/deploy-<project>.lock` prevents simultaneous deploys.
If a deployment is forcibly killed, first verify no deploy is still running,
then remove that empty directory with `rmdir` and rerun deployment. Never delete
the PostgreSQL host directory to recover a deployment.

Run the opt-in, real-container acceptance checks with:

```sh
bundle exec cucumber --profile production_deployment
```

Each scenario uses independent disposable host data, a separate Compose project,
and loopback ports `16435`, `16436`, and `18088`; production/development data are
not used. It checks preparation, pooled connections, assets, asynchronous MCP
execution/projection, environment refresh, delayed expiry, failed deploy recovery,
and data survival across redeployment/container recreation. This topology test runs serially;
the ordinary application test suites retain their fifteen parallel workers.
It explicitly disables telemetry and skips backend startup: tests never use real
Prometheus, Grafana, or Tempo services.

### Observability

The application sends OTLP metrics directly to Prometheus and execution traces
directly to Tempo; there is no Collector. Self-hosted Grafana queries both and
requires no Grafana Cloud account. The pinned backends are Prometheus 3.13.4,
Tempo 3.1.0 (monolithic), and Grafana 13.2.3. The Ruby metrics SDK is still alpha;
backend/library upgrades should rerun the adapter and configuration checks.

For host-run development:

```sh
cp config/development.env.example .env.development
docker compose --env-file .env.development up -d postgres pgbouncer prometheus tempo grafana
set -a
source .env.development
set +a
bin/rails server
```

Export the same file in a separate shell before starting subscriptions:

```sh
set -a
source .env.development
set +a
COORDINATOR_OBSERVABILITY_ROLE=subscriptions bundle exec pg-eventstore subscriptions start -r ./config/environment.rb -r ./config/pg_eventstore_subscriptions.rb
```

Rails does not implicitly load this file. Restart the host-run server and
subscription process after changing their exported settings. If development
ingestion ports are overridden, change the host OTLP endpoint URLs too.
Development Grafana is `http://127.0.0.1:1089/`, initially `admin` / `admin` unless
overridden; change that password on first login. Development also publishes
Prometheus on port 9090 and Tempo's OTLP HTTP receiver on 4318 without additional
network guarding. Do not reuse that exposure policy for untrusted environments.

Production `bin/deploy-production` starts/recreates the three backends after
deploying the app, rereading `.env.production` for both app and backend settings.
Prometheus and Tempo publish no host ports; Grafana alone uses loopback 8089.
Use `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` for its initial local account.
The bootstrap password does **not** rotate an account in an existing Grafana
volume; change it through Grafana's supported account administration.
Application processes have separate finite roles (`web`, `process_managers`,
`task_results`, `read_models`, `jobs`); preparation disables telemetry.

Consumers never depend on backend health. If backend startup fails, deployment
warns after the application is up; inspect/retry those services separately.
The SDK uses bounded queues and fail-open guards. An unavailable sink may lose
telemetry, but must not change command decisions, handler retries, or read
availability. `PRODUCTION_START_OBSERVABILITY=0 bin/deploy-production` skips
backend startup (used by the opt-in deployment tests); it is a CLI-only override
and does not disable app exports. Set `COORDINATOR_OBSERVABILITY_ENABLED=false`
in the selected environment file to disable those too.

Settings are in the development/production examples. Endpoint values are full
HTTP signal URLs, including `/v1/traces` and `/api/v1/otlp/v1/metrics` for these
Ruby exporters. Export interval defaults to 10 seconds (allowed 1–60 seconds),
timeout to 3 seconds (0.1–10 seconds), and trace sampling to 1.0 (0–1). Trace
sampling does not sample metrics. Each process/restart receives a fresh instance
ID, also attached to metrics; long-running deployments incur instance-series
churn. Metrics allow only registered tool/method, subscription/event type,
bounded outcome/SQL operation and process resource labels—never paths,
task/event/correlation IDs, SQL, binds, or payloads.

Open Grafana's **Coordinator / Coordinator observability** dashboard for MCP
outcomes/runtime/in-flight counts, handler throughput/runtime/in-flight age,
delivery age, and Rails SQL throughput/runtime. Builtin Grafana panels and
provisioned Prometheus/Tempo sources require no extra plugins. Example PromQL:

```promql
sum by (subscription_name, outcome) (rate(coordinator_subscription_completed_total[5m]))
histogram_quantile(0.95, sum by (le, subscription_name) (rate(coordinator_subscription_duration_seconds_bucket[5m])))
max by (subscription_name) (coordinator_subscription_oldest_in_flight_seconds)
```

MCP `accepted` is synchronous Task acceptance, not successful async execution.
Handler `ok` is technical delivery success, even when the command it runs records
a business denial. Redelivery counts as another invocation. Delivery age measures
event creation to handler entry and includes intentional replay; a high value or
an idle heartbeat does not prove a stuck handler. Unfinished-handler age instead
measures an actual active invocation with a monotonic clock.

In **Explore / Coordinator Tempo**, TraceQL examples are
`{ name = "mcp tools/call" }` and `{ span.outcome = "error" }`.
SQL spans contain actual start/end times and sanitized `db.query.text` (up to
2048 characters), parented under MCP/handler spans where context exists. Bind
values, raw error messages and event/domain payloads are not exported. Unsafe,
dollar-quoted, malformed or oversized statements omit text but retain timing.
Query-cache hits and `SCHEMA` notifications are excluded; transaction statements
are included. Direct pg_eventstore SQL is not traced. Trace-to-metrics links
filter by process resource attributes; full cross-process Saga trace propagation
and metric exemplars are not promised by this implementation.

Data uses three independent Compose named volumes. Prometheus retains at most
`PROMETHEUS_RETENTION_TIME` (15 days) or `PROMETHEUS_RETENTION_SIZE` (10 GB),
whichever limit applies first; Tempo uses `TEMPO_RETENTION` (168 hours). Retention
is not an instantaneous disk quota: WAL/live traces and housekeeping need extra
space. Volumes survive ordinary container removal, not `down --volumes`, host
disk loss, or a missing backup. This is a minimal single-node filesystem stack,
not HA. [Tempo recommends object storage for production workloads](https://grafana.com/docs/tempo/latest/configuration/);
distributed storage/services need a separately approved deployment plan.

Telemetry tests use the official OpenTelemetry in-memory span/metric adapters
with real application databases and public subscription execution. Static
Compose/provisioning checks do not start the backends. These tests verify
app-generated telemetry, **not** wire ingestion, live Grafana rendering, or
backend durability. To inspect backends after an authorized deployment:

```sh
docker compose --env-file .env.production -f docker-compose.production.yml logs --tail 100 prometheus tempo grafana
```

Solid Queue's public worker/dispatcher/scheduler lifecycle hooks rebuild providers
after fork and flush on child shutdown. Threaded workers share the process's
providers. Tests cannot use network exporters even when inspecting production
settings. For an isolated adapter-overhead sample (no other test suites running):

```sh
OBSERVABILITY_OVERHEAD_REPORT=1 bundle exec rspec spec/lib/coordinator/shared/observability/overhead_spec.rb
```

This reports five alternating warm-path samples per mode for a real MCP read,
two-item batch and artifact title projection. It excludes fixture/provider setup,
uses no timing pass/fail threshold and does not estimate network/backend overhead.

See [Prometheus OTLP configuration](https://prometheus.io/docs/guides/opentelemetry/)
and [Grafana Tempo provisioning](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/provision/)
for the upstream receiver, translation and correlation conventions.

### Native Read projection batching

All 17 Read-model builders consume native ordered batches (up to 1,000 events).
They fold only columns introduced by those facts, then combine compatible patches
into bounded SQL statements in a Read-database transaction. Explicit null clears
a value; absent columns remain unchanged. Stable child identities prevent duplicate
rows. Builders do not revalidate immutable facts, maintain a delivery ledger, infer
a rebuild, reset data, or make availability depend on projection freshness.

To sample isolated patch persistence, with no other test suites running:

```sh
COORDINATOR_BENCHMARK_REPORT=1 bin/parallel-rspec-plain -n 1 spec/lib/coordinator/read/repositories/batch_writer_performance_spec.rb
```

It compares 1,000 individual updates with one compatible bulk patch, reports SQL
and wall time, allocations, RSS change and cluster-wide WAL upper bounds, and
executes captured statements once more with `EXPLAIN (ANALYZE, BUFFERS, WAL)` for
statement-local WAL and trigger measurements. These measurements use test fixtures;
they do not reset PostgreSQL statistics or enforce host-dependent timing thresholds.

### Import your development environment

MCP can act as the repository for your development assets, such as AI skills, user decisions, and build state. To import
them, and this mcp server to your agent, and ask it to move all development into it:

```
Investigate the tools exposed by the <server name> MCP server and import this project's agentic development environment.
Then adjust AGENTS.md to rely on this MCP server for agentic development coordination.
```

Optionally you can ask your agent to create an archived backup of your current agentic dev env, so you can revert it in
case you find this MCP server not a suitable solution.

## Parallel test gates

Prepare fifteen isolated Rails and pg_eventstore database pairs once:

```sh
bin/setup_parallel_tests
```

Run the logical RSpec and Cucumber suites during development, then run the
slower runtime-RBS suite as the final contract gate:

```sh
bin/parallel-rspec-plain
bin/parallel-cucumber
bin/parallel-rspec
```

The parallel workers use explicit numbers 1 through 15. Worker `N` owns
`concurrent_development_mcp<N>_test` and `eventstore<N>_test`; sequential tests
continue to use the unnumbered test databases.

Set the same positive process count for setup and execution to override the
default:

```sh
PARALLEL_TEST_PROCESSORS=4 bin/setup_parallel_tests
PARALLEL_TEST_PROCESSORS=4 bin/parallel-rspec-plain
PARALLEL_TEST_PROCESSORS=4 bin/parallel-cucumber
PARALLEL_TEST_PROCESSORS=4 bin/parallel-rspec
```

Each suite keeps its own smart-runtime timing file. Paths and relevant
`parallel_tests` options may be passed to its runner. The runtime-RBS workers
delegate their file groups to `bin/rspec`, preserving the complete repository
RBS target.

## Development coordination

Repository development instructions and coordination state are provided by the
configured Concurrent Development Coordinator MCP server. Start with `AGENTS.md`.
