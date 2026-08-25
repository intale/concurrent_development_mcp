@operation_batches
Feature: Bounded command batches for checkpointed agent imports
  Agents can move coordination content through typed MCP Tasks without turning a batch into an atomic shortcut.
  Each ordinary target command keeps its own invariant, receipt, and durable denial.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: A Batch Saga resumes from durable facts and crosses bounded process pages

    Scenario: An import-sized Skill batch resumes after duplicate delivery
      When the agent submits a batch of 51 independent Skill publications
      Then the Batch Task accepts all 51 items before target execution
      When the Batch creation is delivered twice and all continuations run
      Then the Batch has 51 successes, no rejection, and one terminal completion

  Rule: Per-item denial does not roll back successes or make available reads wait for convergence

    Scenario: One stale Skill revision is isolated inside an accepted Batch
      When the agent submits two competing initial revisions in one Skill batch
      Then the Batch Task accepts both items before target execution
      When the Batch Saga processes the competing revisions
      And only the first Batch progress facts reach the read side
      Then the available Batch remains running with one observed success
      When the remaining Batch facts reach the read side
      Then the available Batch completes with one success and one rejection
