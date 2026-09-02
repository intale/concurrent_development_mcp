# MCP server for concurrent development

This project enables AI agents to coordinate their work. It does not spawn or orchestrate agents; instead, it provides
functions for recording work that agents plan, start, and finish. It also acts as a repository for development artifacts
such as AI skills, user decisions, documentation, URLs, and other assets produced during development. Checkpointed
development state makes work resumable.

You can import existing AI-related assets and build state, then rely on this MCP server throughout agentic development.
Because the application persists its state in PostgreSQL, it can run in a shared environment and coordinate work across
multiple agents, projects, and locations.

**Attention!** This tool was prompted using AI agent, so treat it accordingly.

## Usage

### Environment setup

Steps to setup the environment(containerization is on its way after I fix major issues):

- start docker compose first via `docker compose up`
- run `./bin/setup_db` to create rails and pg_eventstore databases if this is your initial run
- run `rails s` to start rails server
- run
  `bundle exec pg-eventstore subscriptions start -r ./config/environment.rb -r ./config/pg_eventstore_subscriptions.rb`
  to start pg_eventstore subscriptions

### Import your development environment

MCP can complete take a role of the repo of all your development assets, such as AI skills, use decisions, build state,
etc. In order to do so, start you agent and point it to import your dev environment into MCP(assuming you are running
MCP at `http://localhost:3000`):

```
Investigate tooling at http://localhost:3000/mcp server and import the agentic development environment of this project
into it. After that adjust AGENTS.md to rely on this MCP serve to coordinate agentic development.
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
