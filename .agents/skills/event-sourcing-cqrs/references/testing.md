# Testing Event-Sourced CQRS

## Test ownership

| Layer | Primary test |
|---|---|
| Agent-facing coordination rules | Cucumber through real MCP, PostgreSQL, and `pg_eventstore` |
| Command GWT and reducer behavior | RSpec pure examples linked to Event Model scenario IDs |
| Dry-rb schemas and event compatibility | RSpec boundary/serialization examples |
| Event-store operations, retry races, DCB overlap | RSpec against the real Docker-backed event store |
| Projector idempotency and available stale reads | RSpec against the real read database and subscriptions |
| Process manager event-to-command behavior | RSpec with real source events and live subscriptions |
| Internal Ruby method contracts | `bin/rspec` with application scopes in `RBS_TEST_TARGET` |

Do not mock or stub event stores, databases, Rack/MCP requests, subscription delivery, clocks, ID generation, or other external behavior. Concrete timestamps and IDs supplied by scenarios are inputs, not mocks. Keep reusable test helpers in `spec/support`; keep every `RSpec.configure` block in `spec_helper` or `rails_helper` only.

## Required scenarios

For every command, cover success, each material denial, exact replay, concurrent conflict, and retry exhaustion where relevant. Assert authoritative events separately from eventual views.

For each MCP Task mutation, cover:

- a client without the Tasks capability receives `-32003` and no task/domain facts;
- `tools/call` returns a durable `working` handle before worker completion;
- `tasks/get` resolves immediately from task facts even with read projectors stopped;
- process execution eventually yields the original `CallToolResult` under `completed`;
- duplicate source delivery reuses the target command and produces one logical outcome;
- a domain denial is `completed` with `isError: true`, not `failed`;
- an invalid/unknown Task ID produces `-32602`;
- cooperative cancellation and completion races preserve a terminal state;
- read services return an existing stale view while projectors or the write store are unavailable;
- write commands succeed or return a domain/retryable result while the read database is unavailable.

## Local gates

During TDD run `bundle exec rspec` (and focused Cucumber scenarios as they are added). Do not run the slower typed suite until logical tests pass. At the end of a verified implementation boundary run, in order:

1. `bundle exec rspec`
2. `bundle exec cucumber`
3. `bin/rspec`
4. relevant lint and `rails zeitwerk:check`

Use the repository RVM Ruby/gemset. Commit the scoped boundary only after its required gates pass and build evidence is recorded.
