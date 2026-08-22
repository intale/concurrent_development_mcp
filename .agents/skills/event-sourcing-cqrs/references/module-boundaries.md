# Module and Folder Boundaries

Use this layout under the Zeitwerk-managed `lib/coordinator` root. A nested folder must match its Ruby namespace.

```text
lib/coordinator/
|-- shared/                 Stable technical values used on both sides
|-- write/
|   |-- contracts/          Public command/task input validation
|   |-- commands/           Immutable command values
|   |-- events/             Versioned immutable event schemas
|   |-- domain/             Pure reducers and Given/When/Then deciders
|   |-- event_store/        Bounded criteria and pg_eventstore adapter
|   |-- operations/         Authoritative command execution and retries
|   `-- tasks/              Authoritative MCP Task lifecycle
|-- read/
|   |-- projections/        Projection state/reducers
|   |-- projectors/         Idempotent event-to-view handlers
|   |-- repositories/       Read-store persistence only
|   |-- queries/            Available, possibly stale view access
|   `-- subscriptions/      Read-model registrations
|-- processes/
|   |-- process_managers/   Event-to-command policies/Sagas
|   `-- subscriptions/      Process-manager registrations
|-- mcp/                    Protocol schemas, tools, and transport adapters
`-- container.rb            Composition root

app/models/coordinator/read/   Active Record projection models only
```

The exact leaf folders may be refined when a bounded context becomes large, but the side namespace is mandatory.

## Allowed dependencies

| From | May depend on | Must not depend on |
|---|---|---|
| `Shared` | language and approved libraries | domain write/read code |
| `Write` | `Shared`, `pg_eventstore`, dry-rb | `Read`, Active Record projections, MCP transport |
| `Read` | `Shared`, read database, source event envelope/schema needed for consumption | write operations/deciders, command receipts as mutation authority |
| `Processes` | `Shared`, source event schema, public write command/operation ports | read projections as command truth, event append/factory authority |
| `Mcp` | public write Task ports, public read query ports, MCP SDK | domain internals, Active Record models, raw `pg_eventstore` client |
| composition root | all modules for wiring | business decisions |

`Processes` is an integration layer, not a loophole between CQRS sides. It may read `pg_eventstore` for durable handler idempotency and invoke write operations. The invoked command must reread authoritative facts and decide for itself.

## Shared-kernel test

Put a class in `Shared` only if it is a stable technical primitive whose meaning is identical on both sides, such as canonical JSON or a validated event-envelope identity. Do not put domain state, reducers, repositories, receipts, projection progress, task decisions, or catch-all helpers there merely to bypass the dependency graph.

## Events and schemas

- Keep the authoritative versioned event schema in `Write::Events`.
- The read side may deserialize the event through a narrow shared envelope/registry port; it does not own a competing event definition.
- Place strict dry validation contracts next to the boundary they validate. Public command input belongs to `Write::Contracts`; read-query input belongs to `Read::Contracts` if needed; wire-only MCP envelope shapes belong to `Mcp`.
- Keep task lifecycle facts under `Write::Tasks` unless the task domain grows enough to justify `Write::Events::Tasks` and `Write::Domain::Tasks`; preserve the `Write` ownership either way.

## Read-model availability

Projection identity ledgers, source revisions, markers, and full event envelopes are internal read-side data. They support idempotency, ordering, rebuilds, and diagnosis. Query code must not compare them with a live write-store position to decide whether an existing view can be returned.
