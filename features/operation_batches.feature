@operation_batches
Feature: Bounded command batches for checkpointed agent imports
  Agents can move coordination content through typed MCP Tasks without turning a batch into an atomic shortcut.
  Each ordinary target command keeps its own invariant, receipt, and durable denial.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A Batch Saga resumes from durable facts and crosses bounded process pages

    @CDM-BATCH-001 @AUD-BATCH-RESUME-01 @AUD-BATCH-PAGE-REPLAY-04 @event-contract
    Scenario: An import-sized Skill batch resumes after a page-boundary worker restart
      When the agent submits a batch of 51 independent Skill publications
      Then the Batch Task durably accepts all 51 items
      When the process workers restart after the first durable Batch page
      Then the Batch has 51 successes, no rejection, and one terminal completion
      And Batch number facts record 51 successes and 0 unsuccessful items
      And the complete normalized manifest and outcomes are recoverable in bounded pages using only the Batch ID
      And page-boundary redelivery leaves one marked outcome per item

  Rule: Per-item denial does not roll back successes or make available reads wait for convergence

    @CDM-BATCH-002 @event-contract @stale-view
    Scenario: One stale Skill revision is isolated inside an accepted Batch
      When the agent submits two competing initial revisions in one Skill batch
      Then the Batch Task durably accepts both items
      When the Batch creation reaches the read side while item execution is paused
      Then the available Batch remains running with no observed item outcome
      When the Batch decision boundary is released and terminal facts reach the read side
      Then the available Batch completes with one success and one rejection
      And Batch number facts record 1 successes and 1 unsuccessful items
      And both child command results are independently available through MCP

  Rule: Cooperative cancellation preserves committed item outcomes

    @CDM-BATCH-003 @AUD-BATCH-NOT-RUN-02 @AUD-BATCH-CANCEL-VIEW-03 @event-contract
    Scenario: A bounded remainder is not run after cancellation at a page boundary
      When the agent submits a batch of 51 independent Skill publications
      Then the Batch Task durably accepts all 51 items
      When the first Batch process page completes
      Then 50 item successes and one continuation are durable
      When the agent requests cooperative Batch cancellation
      Then the cancellation Task succeeds without undoing completed items
      And the available Batch exposes accepted cancellation before terminal completion
      When the pending Batch continuation observes cancellation
      Then the Batch history derives 50 successes and one item not run after cancellation
      And Batch number facts record 50 successes and 0 unsuccessful items
      When the agent resubmits only the not-run manifest items
      Then the resumed Batch succeeds once without replaying the completed prefix

  Rule: Batch items retain the ordinary public content contract

    @CONTENT-BATCH-PARITY-04 @event-contract
    Scenario: Single and Batch Skill publication preserve the same Unicode text representation
      When the agent publishes equivalent Unicode Skill assets through single and Batch tools
      Then both Skill commands succeed with semantic version 3 facts
      And the Batch manifest returns the original text-first ordinary command arguments

  Rule: Request identities bind per item and converge across independently accepted work

    @PERF-BATCH-SHARED-01 @event-contract @concurrency
    Scenario: Two accepted batches and an ordinary command share one canonical publication
      When the agent submits two independent batches and one ordinary publication sharing an identical request
      Then all three Tasks succeed and both batches complete
      And the shared request has one canonical publication and a success in each Batch

    @PERF-BATCH-REUSE-02 @event-contract
    Scenario: Reusing a request with changed input rejects only that item after manifest acceptance
      When the agent completes an original Batch request and accepts another Batch with changed input under that request
      Then the second Batch completes with a durable request-reuse denial and an independent success
      And the denied item has no fabricated canonical receipt

  Rule: Cancellation distinguishes an assignment from a committed execution

    @PERF-BATCH-CANCEL-03 @event-contract
    Scenario: Cancellation after assignment prevents execution and permits later resubmission
      When a one-item Batch pauses after its canonical assignment before target execution
      And the agent requests cooperative Batch cancellation
      And the Batch decision boundary is released and terminal facts reach the read side
      Then the assigned item is not run and its canonical command has no terminal effect
      When the agent resubmits only the not-run manifest items
      Then the unexecuted canonical binding is reused successfully

    @PERF-BATCH-RECOVER-04 @event-contract
    Scenario: A worker restart and cancellation reconcile a committed item without its Batch outcome
      When a one-item Batch pauses after its target commits before recording its outcome
      And the agent requests cooperative Batch cancellation
      And the process workers restart after the committed target boundary
      Then cancellation retains one committed success and no item not run
