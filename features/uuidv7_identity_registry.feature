@wip @identity-registry
Feature: Stable coordinator identities with readable natural selectors
  Agents submit domain values to MCP while the coordinator owns UUIDv7 allocation and
  preserves one identity for each exact natural tuple.

  Background:
    Given two MCP agents support checkpointed Tasks

  Rule: Concurrent registration converges on one durable identity

    Scenario Outline: Two agents concurrently register the same natural tuple
      Given both agents independently describe the same <subject> natural tuple
      When they concurrently register that <subject> through MCP
      Then both Tasks complete with the same UUIDv7 identity
      And exactly one registration fact exists for the normalized tuple
      And the fact is selectable by one readable compound marker
      And neither its stream identity nor selector contains a coordinator-generated digest

      Examples:
        | subject                |
        | Repository             |
        | Resource               |
        | Skill                  |
        | Development Artifact   |
        | Artifact relation      |
        | Candidate head         |
        | Merge snapshot         |
        | Verification obligation|

    Scenario: Distinct natural tuples remain independently writable
      Given two agents describe Resources with different normalized paths in one Repository
      When they register both Resources concurrently through MCP
      Then both Tasks complete with different UUIDv7 identities
      And each identity resolves through only its own readable selector

    Scenario: Logical removal does not erase an identity allocation
      Given an exact Resource tuple was registered and later unbound
      When an agent resolves the same Repository, kind, and normalized path again
      Then MCP returns the original Resource UUIDv7
      And no second ResourceRegistered fact is emitted for that tuple

  Rule: Natural-selector encoding is unambiguous and bounded

    Scenario Outline: Similar-looking values remain different selector components
      Given one agent registers a Skill named <first_name> in scope <first_scope>
      And another agent registers a Skill named <second_name> in scope <second_scope>
      When both Skills are resolved through MCP
      Then their readable compound selectors are different
      And decoding each selector returns its exact normalized name and scope

      Examples:
        | first_name | first_scope | second_name | second_scope |
        | a:b        | c           | a           | b:c          |
        | café       | home        | café        | home         |
        | work       | home:team   | work:home   | team         |

    Scenario: An oversized natural selector fails without a digest fallback
      Given an agent supplies a valid UTF-8 natural tuple whose encoded selector exceeds the limit
      When the agent submits the registration through MCP
      Then the Task fails with a stable selector-too-large error
      And no registration fact or shortened digest selector is persisted

  Rule: Digests and external Git object IDs remain evidence rather than identity

    Scenario: Changing Artifact content preserves its identity
      Given a Development Artifact was registered from an exact scope and source locator
      When an agent changes its UTF-8 content through MCP
      Then its Artifact stream keeps the same UUIDv7 identity
      And the server-computed content digest changes only in typed event metadata

    Scenario: A Git object ID can participate in a readable Git selector
      Given an agent registers a Candidate head for a Repository and Git object format
      When the same external head object ID is registered again
      Then MCP returns the original Candidate-head UUIDv7
      And the literal Git object ID is evidence in the readable selector
      And no coordinator digest is derived from that selector

  Rule: A Saga persists generated identities before dispatch

    Scenario: Redelivery reuses a planned child identity
      Given a process step allocated its step, command, and child UUIDv7 identities
      And the process stopped after persisting the plan but before dispatch
      When the source event is delivered again
      Then the process manager resolves the original plan by its readable selector
      And it dispatches the persisted command and child identities unchanged
      And exactly one child registration fact can become visible
