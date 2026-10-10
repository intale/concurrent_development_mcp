Feature: Discover stored development context through bounded literal search
  Agents search available read models using ordinary JSON and retrieve original records.
  Matching stays field-local, scoped, capped and independent of projection freshness.

  Scenario: Retrieve canonical Skill and passive asset hits through MCP
    Given a checkpoint Skill and passive UTF-8 asset have reached the read side
    When an agent searches their name, instructions and asset content with a page size of 1
    Then every search response is immediate, bounded and cursor-followable
    And overlapping Skill matches identify one Skill, separate from the asset
    And canonical retrieval returns the exact stored text without execution

  Scenario: Literal positions, equality and per-literal case flags
    Given a checkpoint Skill and passive UTF-8 asset have reached the read side
    Then the four match positions and case flags have their declared literal meaning
    And percent, underscore, backslash, newlines and Unicode match as ordinary text

  Scenario: Exact scoped discovery for equal names
    Given equal-name checkpoint Skills in two registered Repository scopes
    Then scope and Repository filters intersect without global or cross-scope inclusion

  Scenario: Field-local Boolean exclusions and retained Artifact observations
    Given checkpoint Artifacts with combined, separated and excluded label elements have reached the read side
    Then anchored label conjunctions match one element and exclude the prohibited value
    And selected title and body fields combine by canonical union
    When the first Artifact is updated through MCP with changed checkpoint text
    Then its old observation and current text remain distinctly searchable and retrievable

  Scenario: Available stale projections never gate reads
    Given Skill "search-lag" in scope "project:search-lag" has projected revision 1
    When the agent publishes revision 2 without projecting it
    Then search still serves its projected revision 1
    When the agent attempts another publication from stale revision 1
    Then the stale Skill Task completes with revision conflict and a rejected command lifecycle
    When Skill revision 2 reaches the read side
    Then search returns only the current Skill snapshot

  Scenario: Query-bound opaque cursors cannot be repurposed
    Given a checkpoint Skill and passive UTF-8 asset have reached the read side
    When an agent searches their name, instructions and asset content with a page size of 1
    Then reusing the cursor with a changed exact scope is rejected

  Scenario: Invalid inputs and unanchored exclusions do not schedule Search Tasks
    Then the public MCP search rejects unknown, short, regex and unanchored requests without a Task

  Scenario: A later blocked field cannot produce a misleading partial page
    Given a checkpoint Skill and passive UTF-8 asset have reached the read side
    And checkpoint Guidance has reached the read side
    When the Skills projection table is transactionally locked
    Then the matching Guidance branch does not hide the whole-page budget failure
    When the read transaction lock is released
    Then retrying the same search succeeds
