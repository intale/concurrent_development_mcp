@work-intentions @concurrency
Feature: Independently committed work-intention renewal Sagas
  A renewal is not an all-or-nothing transaction over unrelated Resource streams.
  Agents can inspect partial progress without treating a projection as write-side truth.

  Background:
    Given two MCP agents have active Attempts in the same project
    And agent A has a two-resource shared work-intention set

  Scenario: Withdrawal between renewal steps preserves the first committed extension
    When agent A requests a renewal and withdraws the set after the first member commits
    Then the renewal Task completes with an accountable partial failure
    And the first member keeps its committed extension while the second was not renewed
    And the renewal progress can be discovered using the returned Task ID
    And a stale failed renewal projection remains available
    And replaying the exact renewal request returns the same failed Task

  Scenario: An already satisfied deadline completes without duplicate member facts
    When agent A requests a shorter renewal deadline for the two-resource set
    Then the renewal Task completes successfully with two no-op member outcomes
    And the renewal progress can be discovered using the returned Task ID
