@work-intentions @concurrency
Feature: Advisory resource work intentions
  Agents disclose why they intend to edit resources while the coordinator prevents only
  combinations that planning has declared incompatible.

  Background:
    Given two MCP agents have active Attempts in the same project

  Rule: Shared work is the normal mode

    Scenario: Two agents declare shared work on the same file
      When both agents concurrently declare shared intentions for "config/routes.rb"
      Then both intention Tasks complete successfully
      And each active intention retains its agent, Attempt, purpose, context, and expiry
      And neither agent is promised that its eventual Git changes will merge cleanly

    Scenario Outline: Any overlap with an exclusive intention is rejected immediately
      Given agent A has an active <existing_mode> intention for <existing_resource>
      When agent B declares a <requested_mode> intention for <requested_resource>
      Then agent B receives a modeled incompatible-intention result without a queue or preemption
      And the result identifies every blocker with its resource, mode, owner, Attempt, purpose, context, and expiry
      And no partial intention set is recorded for agent B

      Examples:
        | existing_mode | existing_resource        | requested_mode | requested_resource       |
        | shared        | file app/models/user.rb  | exclusive      | file app/models/user.rb  |
        | exclusive     | file app/models/user.rb  | shared         | file app/models/user.rb  |
        | exclusive     | directory app/models     | shared         | file app/models/user.rb  |
        | shared        | file app/models/user.rb  | exclusive      | directory app/models     |

  Rule: Contention is information for the agent, not a writer queue

    Scenario: Exhausted authoritative history denies declaration and expansion without partial writes
      Given compatible shared work has accumulated more than the intention boundary budget
      When agent B requests a shared intention set declaration over that history
      Then the history-budget Task completes with a typed limit result rather than an execution failure
      And the denied request records no partial intentions or membership changes
      When agent B requests a shared intention set expansion over that history
      Then the history-budget Task completes with a typed limit result rather than an execution failure
      And the denied request records no partial intentions or membership changes

    Scenario: Repeated renewals and withdrawal remain visible when projections catch up
      Given agent A has an active shared intention for file README.md
      When agent A renews that intention twice and withdraws it while read projections are stopped
      Then available Attempt context reflects the latest renewal and withdrawal
      And each renewal receipt retains its own previous and extended deadlines

    Scenario: A blocked exclusive request can be reconsidered after withdrawal
      Given another agent has a shared intention with context explaining its current edit
      When an agent requests an overlapping exclusive intention
      Then the request fails immediately with that context and no pending reservation is created
      When the existing agent withdraws its intention and the requester deliberately retries
      Then the exclusive intention succeeds with a later fencing token

    Scenario: An expired intention cannot block a deliberate retry
      Given an exclusive intention deadline has elapsed without an expiry projector update
      When another agent deliberately declares an overlapping shared intention
      Then the write side rebuilds current intention state from pg_eventstore
      And the new intention succeeds without waiting for a read model or expiry audit
