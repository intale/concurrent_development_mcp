# Given/When/Then for Event Models

Given/When/Then examples make a command decision precise before code or schemas are frozen. They are business examples with concrete data, not test-framework syntax and not a restatement of implementation calls.

## Semantics

- **Given** lists the minimum authoritative event history or reduced state needed for the command decision. Prefer prior domain facts with concrete payloads. Include clock state or attributed external evidence only when the command depends on it.
- **When** contains exactly one command with concrete data and actor/causal attribution. A schedule, incoming external fact, or source event must first be translated into a command.
- **Then** lists the ordered events produced by that command and their concrete payloads. For a denial or semantic no-op, explicitly state that the command returns zero events and name the outcome.
- **Eventually** is optional and separate. Use it for projected views, notifications, downstream commands, and other effects outside the atomic decision boundary.

Do not hide several commands in one `When`, use a projection as authoritative `Given` state, or describe expected events vaguely as “status changes.” No component other than the command decision may produce a domain event.

## Command decision example

```text
Given DescriptionChanged(description: "Old description")
When  ChangeDescription(description: "New description")
Then  DescriptionChanged(description: "New description")
```

If the prior description already equals the command description, `Then` is zero events with an explicit no-change outcome. The event payload comes from the validated command; the decision to emit it comes from comparison with authoritative prior state.

One command may return several events. Validate the complete ordered plan first and persist it through one `PgEventstore::Client#multiple` transaction so no subset can commit.

## Required examples per transition

Create:

1. one success example;
2. one example for every material invariant or denial reason;
3. a semantic retry/idempotency example for public mutations;
4. a concurrency example when commands can race;
5. timeout/expiry and out-of-order examples when time or asynchronous delivery changes the decision;
6. duplicate-delivery and rebuild examples for projections or policies.

Use stable scenario IDs so event contracts, code tests, MCP examples, and documentation can link to the same example.

## State-change template

| Field | Concrete example |
|---|---|
| Scenario ID | `SLICE-NAME-SUCCESS-01` |
| Given | Ordered prior facts and fixed clock/external evidence |
| When | One command with command ID, data, actor, and causal attribution |
| Then events | Zero, one, or ordered multiple event types with full relevant values |
| Then outcome | Stable result or typed denial; state whether facts were appended |
| Eventually | View rows/progress or policy-issued command after a named barrier |
| Consistency proof | Expected revision, DCB selector, or explicit asynchronous boundary |
| Source | Requirement, model transition, and decision references |

## Other Event Modeling patterns

### State view

- Given source facts and an empty or prior-version view.
- When one fact is delivered, including its stable event identity.
- Then the view transaction and processed-event ledger change together.
- On duplicate delivery, Then the view is unchanged and the handler succeeds.

### Automation or policy

- Given the triggering fact and any authoritative policy inputs.
- When the fact is handled.
- Then one or more explicit commands are issued with deterministic identities, or no command is issued because a named predicate is false. The automation emits no domain events itself.
- On duplicate delivery or retry, Then no duplicate logical command is produced.

### External translation

- Given exact incoming/outgoing external evidence and translation version.
- When the external fact is accepted or an outgoing request is prepared.
- Then assert the translated command and preserve source identity for idempotency and audit. Only that command may produce a domain fact.
- Treat external claims as attributed evidence unless the modeled boundary independently verifies them.

## Executability gate

An example is ready to automate when values are concrete, time and identifiers are controllable, event order is explicit, the no-change behavior is observable, and atomic and eventual assertions are separated. The implementation may choose RSpec or another runner, but it must preserve these business semantics.
