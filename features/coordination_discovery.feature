@live-subscriptions
Feature: Project-scoped coordination and Decision discovery
  A clean agent can reconstruct available coordination from an exact project scope.
  Human coordination labels may repeat across projects, while canonical IDs stay globally namespaced.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Project scope is enough to find and resume available coordination

    @AUD-DISCOVERY-CLEAN-CLIENT-01
    Scenario: A clean client discovers current coordination and follows executable actions
      Given project scope "project:audit/discovery-clean" has active checkpointed coordination labeled "shared-build"
      When clean agent "discovery-clean" lists coordination using only that project scope
      Then the agent discovers the active ChangeSet without a remembered coordination ID
      And every discovered coordination action is executable through public MCP
      And the followed context exposes its WorkItem and active Attempt

    @AUD-DISCOVERY-RESUME-02
    Scenario: A replacement client reconstructs interrupted work without local build memory
      Given project scope "project:audit/discovery-resume" has active checkpointed coordination labeled "resume-build"
      When replacement agent "discovery-replacement" lists coordination using only that project scope
      Then the replacement reconstructs the ChangeSet, WorkItem, Attempt, and Candidate checkpoint
      And no Task enumeration or local build file is required

  Rule: Exact scope partitions reusable human labels without becoming a freshness gate

    @AUD-DISCOVERY-SCOPE-03
    Scenario: Two projects reuse one local coordination label without sharing facts
      Given project scopes "project:audit/scope-a" and "project:audit/scope-b" each coordinate local label "same-local-id"
      When clean agents list coordination for their own exact project scopes
      Then each scope returns one distinct canonical ChangeSet for local label "same-local-id"
      And neither scoped result exposes the other project's WorkItem or Attempt

    @AUD-DISCOVERY-STALE-04 @stale-view
    Scenario: Existing discovery remains available while a newer coordination fact awaits projection
      Given project scope "project:audit/discovery-stale" has projected active coordination labeled "stale-build"
      When its read-model subscriptions pause and a Candidate checkpoint commits through MCP
      Then scoped discovery still serves the previously projected coordination
      When read-model subscriptions restart
      Then scoped discovery eventually includes the Candidate checkpoint

  Rule: Decision topics are discoverable beyond the testing framework

    @AUD-DECISION-TOPICS-05
    Scenario: A clean client discovers and resolves a non-testing single-choice topic
      Given project scope "project:audit/decision-topics" has an active "candidate.impact_policy" Decision
      When a clean agent lists active Decisions for that Repository and topic
      Then the non-testing Decision is discoverable with an executable detail action
      And resolving "candidate.impact_policy" returns that exact effective Decision
