@release_set
Feature: Immutable multi-repository ReleaseSet preparation
  Agents prepare one ordered multi-repository plan through a durable Task.
  Authoritative grants are re-evaluated from events while the available ReleaseSet view may lag.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Preparation freezes exact current authorization evidence without coupling writes to projections

    Scenario: Two currently authorized repositories become one traced immutable release plan
      Given ReleaseSet "SUCCESS" has two exact current repository grants for one ChangeSet
      When the agent prepares the ordered ReleaseSet through MCP
      Then the ReleaseSet Task completes with the exact repository order
      And one prepared fact and command completion preserve the Task trace
      And the ReleaseSet remains available as not observed before projection
      When the ReleaseSet preparation reaches the read side twice
      Then the ordered ReleaseSet is available without a freshness gate
