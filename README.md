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

### Environment setup

Steps to set up the development environment:

- start docker compose first via `docker compose up`
- run `./bin/setup_db` to create rails and pg_eventstore databases if this is your initial run
- run `rails s` to start rails server
- run
  `bundle exec pg-eventstore subscriptions start -r ./config/environment.rb -r ./config/pg_eventstore_subscriptions.rb`
  to start pg_eventstore subscriptions

### Production with Docker Compose

Requirements: Docker Engine with Compose v2 (including `up --wait`) and Bash.
The production setup is separate from development/test Compose and runs Rails,
the standalone compiled React UI, three subscription processes, and a dedicated
Solid Queue worker. There is no Node.js server in production.

1. Copy `config/production.env.example` to `.env.production` and set
   `POSTGRES_PASSWORD` and `SECRET_KEY_BASE` to independent random secrets.
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
