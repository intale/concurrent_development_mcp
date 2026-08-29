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

  Rule: Lifecycle changes are explicit and preserve historical identity

    @RES-LIFE-REMOVE-01 @RES-LIFE-REMOVE-REPLAY-01 @RES-LIFE-RECREATE-01 @live-subscriptions
    Scenario: An agent removes and later recreates the same Resource tuple
      When the agent resolves file "app/models/lifecycle.rb" through MCP
      Then the Resource Task returns a server-generated UUIDv7
      When the agent removes the current Resource because it was "removed"
      Then the Resource removal reports "removed" with one unbinding fact
      When the agent repeats the Resource removal because it was "removed"
      Then the Resource removal reports "already_inactive" without another unbinding fact
      When the agent resolves the inactive Resource tuple again
      Then the Resource is reactivated with its original UUID and no new registration

    @RES-LIFE-RENAME-01 @live-subscriptions
    Scenario: Rename remains two explicit commands
      When the agent resolves file "app/models/old_name.rb" through MCP
      Then the Resource Task returns a server-generated UUIDv7
      When the agent removes the current Resource because it was "renamed"
      Then the Resource removal reports "removed" with one unbinding fact
      When the agent resolves renamed file "app/models/new_name.rb" through MCP
      Then the renamed tuple has a distinct current UUID

    @RES-LIFE-KIND-01 @RES-LIFE-KIND-CHANGE-01 @live-subscriptions
    Scenario: Kind change requires removal before resolving the new kind
      When the agent resolves file "docs" through MCP
      Then the Resource Task returns a server-generated UUIDv7
      When the agent tries to resolve directory "docs" through MCP
      Then Resource resolution is denied by the current kind
      When the agent removes the current Resource because it was "type_changed"
      Then the Resource removal reports "removed" with one unbinding fact
      When the agent resolves directory "docs" after removal
      Then the new kind has a distinct current UUID
