---
name: event-modeling
description: Architect or review event-sourced behavior with Event Modeling before defining event contracts or implementation. Use when designing or changing domain events, commands, views, policies, streams, projections, workflows, or event-sourced acceptance tests; especially when a proposed event catalog must be validated against user journeys and concrete examples.
---

# Event Modeling

Use Event Modeling to derive event-sourced behavior from an end-to-end story. Treat an existing event catalog as input to review, not as the model itself.

## Command-only event production

- Every persisted domain event must be the result of exactly one command decision. No controller, projector, subscription handler, Saga/process manager, scheduler, event factory, or other arbitrary component may decide or append a domain event directly.
- Implement a command as the Event Modeling Given/When/Then decision: **Given** authoritative prior events/state, **When** one command is applied, **Then** return zero, one, or multiple new events.
- A denial or semantic no-op returns zero events. The command result must still make the outcome explicit according to the accepted idempotency contract.
- A Saga/process manager reacts to an event by issuing deterministic command(s). Each target command rereads authoritative state and decides its own events.
- Validate the complete event-write plan before appending. For one stream, append its one-or-many events atomically with the expected revision covering the authoritative read. When consistency spans two or more streams in one `pg_eventstore` config, persist the complete plan through one `PgEventstore::Client#multiple` transaction. Across configs/connections, model an asynchronous boundary instead.
- An event factory may serialize a command's validated event plan; it has no event-producing decision authority.

For any system or feature with more than one state transition, read [references/modeling-workbook.md](references/modeling-workbook.md) and use its artifact structure.

For event-sourced work, also read:

- [references/given-when-then.md](references/given-when-then.md) to turn every modeled decision and reaction into concrete executable examples;
- [references/dynamic-consistency-boundaries.md](references/dynamic-consistency-boundaries.md) to decide whether an invariant belongs to one static stream or a boundary selected dynamically from event types and markers.

## Workflow

1. Establish the business outcome, time horizon, actors, external systems, and modeling boundary.
2. Storyboard the happy-path chronology with immutable, past-tense business facts. Avoid implementation events and CRUD names.
3. Add the inputs that cause facts: actor intent, schedules, incoming external facts, and the commands they invoke. Distinguish inputs, commands, and events; every fact must point to its producing command.
4. Add the views or other outputs needed before each decision. Do not let a projection become an unstated source of command truth.
5. Add policies and automations that react to facts and issue commands. They never append downstream domain events directly. Show external-system translations explicitly as input-to-command edges.
6. Put behavior into swimlanes, then mark consistency and ownership boundaries. For each invariant, deliberately select a static stream, a Dynamic Consistency Boundary, or an explicit cross-boundary process. Derive aggregate and stream choices afterward.
7. Put representative data on every input, event, and view. Trace every event field to command data, prior authoritative state, a deterministic policy, or external evidence.
8. Add alternate, denial, retry, timeout, and concurrency paths. A denied command is an outcome, not automatically a persisted domain event.
9. Cut the timeline into small, testable vertical slices. Each slice must produce observable value and fit one of: state change, state view, automation, or external translation.
10. Turn each command into Given/When/Then examples before freezing event schemas or writing implementation code. `Given` describes authoritative prior facts/state, `When` applies exactly one command, and `Then` asserts its ordered events or an explicit zero-event outcome; assert eventually consistent views and Saga-issued commands separately.

## Required outputs

Produce and maintain:

- a legend and scope statement;
- a big-picture chronological model;
- detailed swimlane models for each boundary;
- concrete data examples and data-provenance checks;
- vertical-slice definitions and Given/When/Then scenario tables;
- a derived command/event/view/policy catalog;
- a command-to-event matrix proving that every event has one producing command;
- static-stream or Dynamic Consistency Boundary decisions, including retry and concurrency proofs;
- consistency, ownership, retry, and idempotency annotations;
- unresolved questions and links to source requirements and decisions.

Use compact Markdown tables when a collaborative canvas is unavailable. Diagrams may supplement the tables, but never replace concrete examples and scenarios.

## Contract gate

Do not mark an event contract implementation-ready until its model identifies:

- the triggering input or prior event;
- the one command whose decision produces the event;
- actor or policy and authorization/invariant decision;
- example payload and provenance for every field;
- owning boundary and intended stream/aggregate;
- immediate and eventual consumers;
- consistency and ordering expectations;
- whether the command writes one stream with optimistic expected revision, two or more streams through one same-config `Client#multiple`, or crosses configs through an asynchronous process;
- the selected consistency pattern and, for a Dynamic Consistency Boundary, its exact event-type/marker selector;
- duplicate, retry, and concurrency behavior;
- executable Given/When/Then examples for success and every material invariant, plus retry/concurrency cases where relevant;
- schema evolution or versioning treatment.

When changing an implemented event, update the model and affected scenarios first, then assess compatibility, migrations, projections, integrations, and rebuilds.

## Review rules

- Flag aggregate-first or lifecycle-first event catalogs that lack chronology, commands, views, and examples.
- Flag events named as requests, statuses, implementation mechanics, or mutable state rather than facts.
- Flag fields without an authoritative source.
- Flag automations hidden inside projectors or reducers.
- Flag any domain event appended or decided outside a command execution.
- Flag events without exactly one producing command, single-stream plans without an expected revision covering the read, and multi-stream plans that do not use same-config `Client#multiple` or an explicit asynchronous boundary.
- Flag cross-boundary synchronous assumptions and missing eventual-consistency behavior.
- Flag invariants that depend on a projection or broad scan when a static stream or precisely selected Dynamic Consistency Boundary is required.
- Flag payload scans used only to differentiate events that could be selected by a stable marker, and flag multi-marker selectors that incorrectly assume AND semantics instead of using a compound marker.
- Flag Dynamic Consistency Boundaries whose competing commands do not demonstrably select an overlapping serialized event set.
- Flag Given/When/Then scenarios that use vague state, combine multiple commands in `When`, or mix atomic facts with eventual projection assertions.
- Flag slices that cannot be demonstrated through an input, resulting facts, and observable output.
- Keep requirements, modeled decisions, provisional design choices, and implementation details visibly distinct.
