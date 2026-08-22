---
name: event-sourcing-cqrs
description: Implement or review Rails event-sourced CQRS code and tests after an Event Model is accepted. Use for commands, events, event-store adapters, process managers, projections, queries, MCP Tasks, retries, and module-boundary changes; do not use it to invent the domain chronology before Event Modeling.
---

# Event Sourcing CQRS

Implement an accepted Event Model as an explicitly separated event-sourced write side, eventually consistent read side, process layer, and transport layer. If commands, events, policies, views, or invariants are not yet modeled with concrete Given/When/Then examples, use the `event-modeling` skill first and stop at its contract gate.

## Required architecture

- Treat `pg_eventstore` as the write side's only source of truth. A command decision may read only bounded authoritative events selected by a static stream or a modeled Dynamic Consistency Boundary.
- Keep the read side available and eventually consistent. Serve an existing projection without comparing it with the write store, withholding stale content, or exposing a `pending_projection` gate.
- Only a command decides domain events. A process manager consumes an event and invokes a deterministic command; a projector updates a disposable view; neither appends downstream domain events directly.
- Put MCP Tasks and their authoritative lifecycle in the write side. Task polling reads task facts from `pg_eventstore`, never a projection. Keep ordinary query tools on the read side.
- For explicit expected-revision writes outside `Client#multiple`, bound public `WrongExpectedRevision` retries, reread and re-decide with stable logical IDs/times, and return a typed retryable outcome after exhaustion. Do not reinterpret or wrap `Client#multiple`'s internal serialization/deadlock transaction restarts as public retries.
- Keep the composition root as the only place that wires across sides. Do not hide cross-side access behind a shared repository or generic service.

Before moving or adding application code, read [references/module-boundaries.md](references/module-boundaries.md). When implementing commands, subscriptions, Tasks, or schemas, also read [references/implementation-patterns.md](references/implementation-patterns.md). Before writing or reorganizing tests, read [references/testing.md](references/testing.md).

## Implementation sequence

1. Link the slice to accepted Event Modeling artifacts, decisions, GWT scenario IDs, and its selected consistency boundary.
2. Classify every class as shared, write, read, process, MCP transport, or composition root; correct dependency violations before adding behavior.
3. Define strict dry-rb input, command, event, and persisted protocol schemas. Use RBS—not internal runtime class guards—for trusted internal method contracts.
4. Implement pure reducers/deciders, then the bounded event-store operation and finite conflict translation. Persist a command's multi-event plan atomically with `PgEventstore::Client#multiple`.
5. Implement process managers and projectors as separate subscribers with stable, unique `(subscription_set, subscription_name)` identities.
6. Expose the behavior through MCP. Mutations create durable Tasks before returning a handle; queries serve the latest read-side state without write-side freshness checks.
7. Verify the acceptance invariant through real MCP, PostgreSQL, and `pg_eventstore`; verify lower layers through RSpec and RBS instrumentation.

## Review gate

Reject an implementation when:

- the write side reads an Active Record projection, cache, query object, or read-side status;
- the read side must contact the write store before serving an existing view;
- a transport, projector, or process manager constructs/appends a downstream domain event;
- an unbounded history read or payload scan substitutes for a modeled stream/marker selector;
- an application-owned expected-revision retry loop is unbounded or reuses mutable event instances;
- a task handle is returned before its authoritative task fact is queryable;
- a logical/tool error is represented as MCP Task `failed` instead of terminal `completed` with the original tool result;
- module names and paths do not match Zeitwerk, or application code uses `require`/`require_relative` dependency wiring;
- tests replace real event-store, database, subscription, or MCP behavior with fakes, mocks, or stubs.
