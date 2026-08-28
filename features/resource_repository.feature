Feature: Server-owned Resource identities
  Agents resolve Repository paths without computing Resource IDs, digests, markers, or timestamps.
  The write side remains authoritative and available while read projections lag or are stopped.

  Background:
    Given an MCP agent supports checkpointed Tasks
    And a registered Repository is available for Resource resolution

  Rule: One exact tuple has one server-owned identity

    @RES-ID-NEW-01 @RES-ID-REPLAY-01 @RES-ID-LAG-01 @live-subscriptions
    Scenario: Resolution succeeds and replays while read-model subscriptions are stopped
      Given read-model subscriptions are stopped for Resource resolution
      When the agent resolves file "app/models/account.rb" through MCP
      Then the Resource Task returns a server-generated UUIDv7
      And one registration and binding pair is durable in that Resource stream
      When the agent resolves the same Resource tuple with another command
      Then the second Resource Task returns the same UUID without another Resource fact

    @RES-ID-RACE-01 @live-subscriptions
    Scenario: Two agents concurrently resolve the same previously unseen tuple
      When two agents concurrently resolve file "app/services/ledger.rb" through MCP
      Then both Resource Tasks succeed with one canonical UUID
      And exactly one registration and binding pair exists for the contended tuple
