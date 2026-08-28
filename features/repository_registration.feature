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

  Rule: Exact scope is sufficient for clean agents to discover coordination identity

    Scenario: Two clean agents discover the same canonical Repository without host paths
      Given a caller-created Repository is registered for scope "project:payments/workspace:primary"
      And the Repository registration reaches scoped discovery
      When two clean agents independently list Repositories using only that scope
      Then both agents discover the same canonical Repository and attributed metadata
      And Repository discovery stays available without a freshness contract

  Rule: Public discovery is the executable coordination contract

    @AUD-MCP-SCHEMA-ACTOR-01
    Scenario: Actor kinds match the mutation validators exactly
      Given an agent inspects current MCP discovery
      Then agent-only mutation families advertise only agent attribution
      And Batch cancellation advertises exactly agent or user attribution

    @AUD-MCP-SCHEMA-REPOSITORY-02
    Scenario: Every Repository identity is a canonical UUIDv7
      Given an agent inspects current MCP discovery
      Then every discovered Repository identity field requires UUIDv7

    @AUD-MCP-SCHEMA-UTF8-03
    Scenario: UTF-8 byte limits are enforced before asynchronous work exists
      When an agent registers a Repository with a multibyte scope beyond its advertised byte limit
      Then the byte-invalid request is rejected before allocating a Task

    @AUD-MCP-OUTPUT-TASK-04 @live-subscriptions
    Scenario: Terminal Task output is valid for its originating mutation
      When the agent registers a caller-created Repository for scope "project:audit/mcp-contract"
      Then the Repository Task completes with the exact attributed metadata
      And its terminal result is valid for the discovered repository_register output schema
