# Implementation Patterns

## Command path

Implement one state-changing intent in these layers:

1. A strict `Dry::Validation::Contract` validates untrusted input and constructs an immutable dry-rb command value.
2. A bounded event criterion names exact stream/type/marker selection and its maximum cardinality.
3. A pure reducer builds authoritative state from those events.
4. A pure decider applies one command and returns a typed zero/one/many event plan plus an explicit outcome.
5. An operation executes the read/decide/append unit. It creates stable IDs and timestamps before retryable work, instantiates fresh event objects on each attempt, and commits a multi-event plan with one `Client#multiple` call.
6. When the operation uses an explicit expected revision outside `Client#multiple`, a finite application retry policy translates `WrongExpectedRevision` exhaustion into a typed result stating that nothing committed and a later retry may succeed.

Do not use a read model, projected receipt, cache, or transport state to authorize the decision. Semantic no-op/denial commands return zero domain events unless the accepted Event Model defines an audit fact; a separate task-outcome command may persist the protocol lifecycle result.

`Client#multiple` is a SERIALIZABLE transaction facility. Put the complete bounded read-condition-write decision inside its block, do not pass expected revisions inside it, and let `pg_eventstore` own its internal serialization/deadlock restarts. Prepare retry-stable logical values before the block and construct fresh event instances during each execution. Do not add an application counter around those internal transaction restarts.

## MCP Task path

Model Tasks as a write-side durable state machine:

```text
tools/call with Tasks capability
  -> SubmitTask command
  -> TaskSubmitted fact is queryable
  -> CreateTaskResult(status: working)

TaskSubmitted
  -> task-executor process manager
  -> invokes the modeled target command
  -> RecordTaskOutcome command
  -> TaskCompleted or TaskFailed fact

tasks/get
  -> bounded Task-stream fold from pg_eventstore
  -> working/completed/failed/cancelled protocol shape
```

- Return `CreateTaskResult` only after `TaskSubmitted` is committed and `tasks/get` can resolve it.
- Use a high-entropy server-generated Task ID and treat it as a bearer handle. Do not provide task enumeration.
- Store only modeled request data and outcome facts, not raw conversations or incidental transport traffic.
- The executor is a process manager: it invokes commands and never appends target or task events directly.
- Derive deterministic target command identity from the Task fact so delivery retries do not duplicate a logical command.
- After target execution, invoke a separate task-outcome command. If the worker crashes between these operations, redelivery reuses the target command identity and converges through its durable result.
- `tasks/get` is an authoritative write-side query, not an eventually consistent projection. It returns the protocol `resultType: complete` wrapper required for polling.
- A tool-level denial/error is a terminal `completed` Task whose original `CallToolResult` has `isError: true`; only a JSON-RPC execution error becomes `failed`.
- `tasks/update` accepts/ignores response keys according to the extension. If no modeled command currently asks for input, no task reaches `input_required`.
- `tasks/cancel` records cooperative intent through a command when the Task exists. A worker may still win the race and complete; terminal states never change.
- Require `io.modelcontextprotocol/tasks` in each relevant request's client-capability metadata. Return JSON-RPC `-32003` with `requiredCapabilities` when absent. Advertise the extension through `server/discover`.

## Process managers and subscriptions

- Give each event-to-command reaction a deterministic decision identity derived from the complete source event identity and target command purpose.
- Use DCB plus a decision marker only when the modeled idempotency invariant spans a dynamic set. Otherwise a task/command stream and stable command ID are sufficient.
- Stack subscriptions in one manager per semantic set. Keep `(subscription_set, subscription_name)` globally intentional and unique within the set.
- Prefer separate semantic sets for process managers and read projectors; split them into separate OS processes only for measured capacity/isolation needs.
- Use the installed `pg-eventstore subscriptions` CLI for lifecycle.

## Projection path

Projectors atomically claim an exact source-event identity with their view update. Duplicate delivery succeeds without changing the view. Queries return the latest existing view immediately; projection progress may be included as diagnostic metadata only when it does not gate or suppress content.
