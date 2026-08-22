# Dynamic Consistency Boundaries

Event Modeling identifies a decision, the facts it needs, and the invariant it protects. A Dynamic Consistency Boundary (DCB) is an implementation pattern for decisions whose authoritative event set is selected from the command context rather than permanently contained in one aggregate stream.

DCB complements Event Modeling; it does not replace timelines, event examples, or business invariants.

## Choose the consistency pattern deliberately

| Situation | Prefer |
|---|---|
| One stable entity/stream contains every fact needed for the invariant | Static stream with optimistic expected revision |
| The invariant covers a command-dependent set of resources/entities and conflicting commands can select an overlapping event set | Dynamic Consistency Boundary |
| Independent boundaries coordinate over time and temporary inconsistency is valid | Explicit policy/process with compensating or blocking states |
| The check is only for presentation and may be stale | Projection/query; never use it as authoritative invariant enforcement |

Do not introduce DCB merely to avoid modeling ownership. Do not create a global stream or broad marker that serializes unrelated work.

## Model a DCB

For each candidate DCB:

1. Name the invariant in business language and the commands that can violate it.
2. List the authoritative event facts needed to decide, including facts that release, expire, supersede, or invalidate earlier claims.
3. Define stable event types and markers/tags used to select those facts.
4. Show how command data produces the dynamic selector. Normalize keys before selection.
5. Prove overlap: any two commands that could jointly violate the invariant must select at least one common serialized event set/partition.
6. State the maximum selected keys/events and reject or partition commands that exceed the bound.
7. Define the zero/one/many events returned by the command decision. If it returns multiple events, append the validated plan atomically through `Client#multiple`.
8. Define retry behavior: reread the boundary, rebuild state, and reevaluate the command; never reuse mutable event instances.
9. Add Given/When/Then concurrency examples that demonstrate one winner or the intended compatible result.

Record the result:

| Field | Required detail |
|---|---|
| Transition and slice | Links to the Event Model |
| Invariant | The business rule protected atomically |
| Competing commands | Every command that can affect the rule |
| Event types | Exact authoritative fact types read |
| Markers/tags | Exact stable keys and normalization/version rules |
| Dynamic selector | Mapping from command/prior facts to selected sets |
| Appended facts | Events written in the same serializable unit |
| Overlap proof | Why conflicting commands serialize |
| Bounds | Maximum markers, streams, facts, and retry budget |
| Scenarios | Success, compatible parallelism, conflict, and retry IDs |

## PostgreSQL / pg_eventstore mapping

When the application uses `pg_eventstore`:

- perform authoritative reads and appends within `PgEventstore.client.multiple`;
- express the boundary with the narrowest event-type and marker criteria that preserve the overlap proof;
- use a stable, normalized marker when one event type must be selected by a payload discriminator such as locale, repository, policy, or resource identity; do not load every event of that type and scan its payload to reconstruct the selector;
- remember that a marker list is matched with OR semantics. When the decision requires several dimensions simultaneously, derive one versioned compound marker from the complete normalized tuple and select by that marker; separate component markers do not express an AND condition;
- use the same marker derivation for reads, writes, and expected-revision/DCB selectors, and retain the discriminating fields in the event payload as domain data rather than treating the marker as the only record of them;
- do not pass per-stream expected revisions inside `multiple`;
- do not consult Active Record projections to decide the invariant;
- prepare stable logical IDs and times outside the retryable block, then instantiate fresh events from those values on every attempt;
- assume the serializable block can rerun, including when a new event-type partition is created;
- keep the read-condition-write work bounded. Treat `Client#multiple`'s internal serialization/deadlock restarts as part of its SERIALIZABLE transaction implementation; do not wrap them in an application retry counter. Only explicit expected-revision workflows outside `multiple` expose a bounded application retry/exhaustion outcome.

Only a command execution appends events inside the DCB transaction. A Saga/process manager, projector, subscription handler, scheduler, or transport may invoke that command but may not decide or append its downstream events.

### Compound-marker convention

Treat a compound marker as a third marker representing the conjunction of its component markers; keep the component markers on the event when their individual lookups are also useful. Define one project convention rather than concatenating arbitrary strings ad hoc. A robust convention:

1. normalize each complete component marker according to its own dimension;
2. remove duplicates and byte-sort the components, because conjunction is order-independent;
3. construct a named versioned document containing `schema`, `purpose`, and the ordered `components`;
4. hash its canonical encoding; and
5. format the physical marker as `compound:<purpose>:v1:sha256:<lowercase-hex>`.

The purpose distinguishes different conjunction meanings even when their components happen to match. Do not nest compound markers as components. Persist or otherwise freeze the document schema and canonicalization rules so every writer, reader, and revision selector derives identical marker bytes.

Use a static stream instead when its revision already provides the needed contention boundary. Use `multiple` across a small fixed set of streams when atomicity spans those streams but no dynamic event selector is needed.

## Required proof scenarios

At minimum, specify and automate:

- two conflicting commands start from the same state: one commits and the other retries into a denial or updated valid decision;
- two compatible commands select disjoint boundaries and both commit;
- a retry emits the same logical event identities and no duplicate facts;
- release/expiry/invalidation facts change the next decision correctly;
- marker normalization makes semantically identical resources overlap;
- a command above the declared boundary size fails before entering an unbounded transaction.

Failure to demonstrate overlap means the DCB does not protect the invariant. Broaden or redesign the selector, introduce a narrow registry stream, or move the behavior to an explicit asynchronous process.
