Feature: Scoped repository registration
  Agents identify repositories with caller-created UUIDv7 values and exact coordination scopes.
  Paths, names, and remotes remain attributed metadata because the server may run outside the project host.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: The caller supplies the canonical repository identity and scope

    Scenario: An agent registers a repository that is outside the server container
      When the agent registers a caller-created Repository for scope "project:payments/workspace:primary"
      Then the Repository Task completes with the exact attributed metadata
      And one scoped Repository fact is durable without a server-derived location

    Scenario: A human repository label is not accepted as canonical identity
      When the agent tries to register Repository identity "payments"
      Then registration is rejected before a Task or coordination fact exists

  Rule: A repository identity cannot be rebound

    Scenario: A retry replays while another scope is rejected
      Given a caller-created Repository is registered for scope "project:payments/workspace:primary"
      When the agent retries the exact Repository command
      Then the retry exposes the original result without another Repository fact
      When the agent tries to bind that Repository identity to scope "project:other/workspace:primary"
      Then the conflicting Task completes with Repository identity conflict
      And the rejected command writes no command fact
