@production_deployment
Feature: Production deployment preserves checkpointed coordination
  Production uses persistent PostgreSQL behind transaction-mode PgBouncer,
  independent subscription processes, a queue worker, and a Ruby-served client UI.

  Background:
    Given an independent production deployment with disposable host data

  Scenario: Fresh preparation creates every required database through PgBouncer
    Then all four production databases have their application schemas
    And the five independent consumers are running after preparation
    And both published database ports are bound only to loopback

  Scenario: Rails serves the standalone compiled React application
    Then production serves the React mount and its JavaScript and CSS
    And stable UI entry assets require revalidation
    And the production application image has no Node.js runtime

  Scenario: Agent documentation survives redeployment and database container recreation
    When an agent stores UTF-8 documentation through production MCP
    Then the asynchronous Task completes and its projected content becomes available
    When production is deployed again and its database containers are recreated
    Then the same documentation and completed Task are still available
    And repeating the agent command returns the same documentation identity

  Scenario: The separate queue worker expires an agent work intention
    When an agent declares a work intention lasting thirty seconds through production MCP
    Then the real delayed job is scheduled in the queue database
    And the queue worker finishes it and records the bounded expiry fact

  Scenario: Failed preparation leaves existing consumers stopped without deleting data
    When an agent stores UTF-8 documentation through production MCP
    And deployment preparation is intentionally misconfigured
    Then deployment fails without restarting consumers
    When the valid production configuration is deployed again
    Then the same documentation and completed Task are still available
