# Event Modeling Workbook

Use this workbook for a substantial system or any feature spanning multiple state transitions. Copy only the relevant sections into the project's design artifacts.

## 1. Scope and legend

Record:

| Field | Meaning |
|---|---|
| Outcome | The measurable user or business result |
| Start / end | Where this timeline begins and ends |
| Actors | People or autonomous agents providing intent |
| External systems | Sources or destinations outside the modeled boundary |
| Lanes | Business capabilities or ownership boundaries, not code folders |
| Evidence | Requirement and decision references used to justify the model |

Use these card types consistently:

| Card | Meaning | Naming |
|---|---|---|
| Input | Human or external information entering the story | Noun phrase |
| Command | Intent to change authoritative state | Imperative verb phrase |
| Event | Immutable business fact that occurred | Past-tense verb phrase |
| View | Information presented for a decision or observation | Noun phrase |
| Policy | Deterministic reaction from facts to commands | “When … then …” |
| External translation | Mapping at a system boundary | Source and destination named |

Only commands produce domain events. Policies, external translations, schedules, and subscriptions produce or invoke commands.

## 2. Big-picture chronology

Start with the primary success story. One row is a moment in time, not an entity definition.

| Seq | Lane | Actor / trigger | Input or command | Event facts | Resulting view / output | Requirement refs | Questions |
|---:|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |

Then add alternate and failure paths without destroying the readability of the success story. Link detailed paths from the relevant row.

## 3. Detailed transition cards

Create one record for every state-changing decision:

| Field | Required detail |
|---|---|
| Transition ID | Stable model-local identifier |
| Upstream trigger | Actor input, schedule, prior event, or external fact that invokes the command |
| Producing command | The single command whose decision returns the event plan |
| Decision owner | Actor, aggregate, policy, or external authority |
| Required view/state | Exact information used to decide |
| Preconditions | Authorization and business invariants |
| Resulting facts | Ordered event list, or no event for denial |
| Write plan | Single-stream expected-revision append (one or many events), same-config multi-stream `Client#multiple`, or asynchronous cross-config process |
| Consistency | Atomic facts and boundaries crossed asynchronously |
| Concurrency | Expected version, lock, uniqueness, or conflict rule |
| Consistency pattern | Static stream, Dynamic Consistency Boundary, or explicit cross-boundary process |
| Retry/idempotency | Stable identity and duplicate response |
| Observable result | View, receipt, notification, or external effect |
| Evidence | Source requirement and decision links |

## 4. Concrete examples and provenance

Show representative JSON-compatible values, including identifiers, times, versions, and boundary cases. For every emitted event field, complete:

| Event field | Example | Authoritative source | Transformation | Stability / sensitivity |
|---|---|---|---|---|
|  |  | command, prior event/state, policy, or external evidence |  |  |

Reject a design if a required event field can only be obtained from a lossy projection, nondeterministic ambient state, or an unspecified source.

## 5. Views and automations

For each view, identify source events, freshness expectations, rebuild behavior, ordering, and how absence or lag is shown.

For each automation, identify:

- triggering event and subscription position;
- predicate and authoritative inputs;
- command issued and stable idempotency identity;
- retry, poison-message, and observability behavior;
- whether the reaction crosses a consistency boundary.

Projectors build views; they do not secretly issue commands or events. If a reaction is required, model it as a named policy/process with an explicit event-to-command edge. The target command alone decides downstream events.

## 6. Vertical slices

Prefer the smallest end-to-end slice that a stakeholder can observe:

| Slice | Pattern | Input | Facts | Output | Dependencies | Acceptance scenarios |
|---|---|---|---|---|---|---|
|  | state change / state view / automation / translation |  |  |  |  |  |

A slice is ready to plan when it has concrete data, a clear ownership/consistency boundary, and executable scenarios. Infrastructure may be introduced by the first slice that needs it; do not create disconnected horizontal layers as milestones.

For every state-changing slice, record the pure decision shape:

```text
decide(authoritative Given history/state, one When command)
  -> zero, one, or multiple Then events
```

Choose atomicity by consistency topology, not event count. Append one or many events to one stream with the expected revision covering the read. Use one `PgEventstore::Client#multiple` transaction when the command writes two or more streams in the same config. A boundary spanning configs/connections cannot use `multiple` and must coordinate asynchronously.

## 7. Given/When/Then scenario format

Use one table per slice:

| Scenario | Given authoritative history/state | When | Then facts | Then observable output | No-change / error expectations |
|---|---|---|---|---|---|
| success |  |  |  |  |  |
| denial |  |  | none | typed error/receipt | stream and views unchanged |
| retry | prior success exists | same logical command | no duplicate facts | same logical result | stable identity |
| conflict | competing version/claim | command | domain-specific result | actionable conflict | no partial write |

Add timeout, out-of-order delivery, replay, and external failure scenarios where relevant.

Keep atomic and eventual assertions distinct. `Then facts` covers the authoritative transaction; `Then observable output` may require a projection barrier or an explicit `Eventually` step. Apply the detailed rules in `given-when-then.md`.

## 8. Dynamic Consistency Boundary worksheet

For every invariant, first decide whether one static stream owns all decision facts. If the protected event set varies with command data, complete:

| Transition | Invariant | Competing commands | Event types read | Stable markers/tags | Dynamic selector input | Facts appended | Overlap/concurrency proof | Bound/cardinality |
|---|---|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |  |  |

A Dynamic Consistency Boundary is valid only when all commands that could violate the same invariant select an overlapping serialized set, re-evaluate after retry, and do not use an eventually consistent view as authority. Apply the detailed rules in `dynamic-consistency-boundaries.md`.

## 9. Derived catalog and implementation handoff

Only after the timelines and scenarios agree, derive catalogs for commands, events, views, policies, streams, and tools/APIs. Each catalog entry links back to transition and slice IDs.

Before implementation, verify:

- every event appears on at least one timeline and in one scenario;
- every event has exactly one producing command and every command lists its zero/one/many event outcomes;
- every command has a decision owner and success/denial behavior;
- every view supports a modeled decision or observable outcome;
- every automation is explicit and idempotent;
- every cross-lane edge names its consistency behavior;
- every invariant names its static stream, Dynamic Consistency Boundary, or explicit process boundary and includes a concurrency proof;
- every event field passes provenance review;
- proposed stream boundaries preserve each modeled invariant;
- unresolved choices are recorded as decisions or gates, not hidden assumptions.
