@candidate_impact
Feature: Attributed potential impact between Candidate checkpoints
  Agents publish semantic-impact evidence through durable Tasks and coordinate from an available directional view.
  A relationship is attributed and unverified; it is never a verified incompatibility, obligation, or merge decision.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Impact evidence is authoritative while its read model remains independently available

    Scenario: A traced surface commits while the previously observed Candidate remains readable
      Given impact ChangeSet "SURFACE" has these projected Candidate checkpoints:
        | role   | candidate_id        | repository | head | path       | observes_path |
        | source | CAN-CUC-IMP-SURFACE | billing    | b    | lib/api.rb | yes           |
      When analyzer "analyzer-7" submits this impact evidence for "source":
        | direction | impact_key              | value     |
        | produces  | contract:payments-api:v2 | available |
      Then the impact Task completes with attributed unverified evidence
      And the surface and successful command lifecycle preserve the Task trace
      And the previously observed Candidate is still served without the new surface or a freshness gate
      When the "source" impact fact reaches the read side
      Then the available "source" surface preserves attributed evidence without a freshness claim

  Rule: Potential relationships aggregate exact evidence and cross repository boundaries only by semantic key

    Scenario: One source pages a path target and a cross-repository semantic target
      Given impact ChangeSet "MATCH" has these projected Candidate checkpoints:
        | role            | candidate_id              | repository | head | path                    | observes_path |
        | source          | CAN-CUC-IMP-MATCH-SOURCE  | billing    | b    | contracts/payments.json | no            |
        | path_target     | CAN-CUC-IMP-MATCH-PATH    | billing    | e    | contracts/payments.json | yes           |
        | semantic_target | CAN-CUC-IMP-MATCH-CHECKOUT | checkout   | f    | lib/payments_client.rb  | no            |
      When these attributed impact surfaces are submitted and projected:
        | role            | direction | impact_key               | value     |
        | source          | produces  | contract:payments-api:v2 | available |
        | path_target     | consumes  | contract:payments-api:v2 | required  |
        | semantic_target | consumes  | contract:payments-api:v2 | required  |
      Then outgoing potential impacts from "source" page exact path and semantic reasons once
      And incoming potential impact to "semantic_target" points across repositories to "source"

  Rule: Command replay and concurrent decisions cannot duplicate a Candidate surface

    Scenario: Exact retry returns the original surface through its original Task
      Given impact ChangeSet "REPLAY" has these projected Candidate checkpoints:
        | role   | candidate_id       | repository | head | path          | observes_path |
        | source | CAN-CUC-IMP-REPLAY | billing    | b    | lib/replay.rb | no            |
      When analyzer "analyzer-7" submits this impact evidence for "source":
        | direction | impact_key               | value     |
        | produces  | contract:payments-api:v2 | available |
      And the exact impact command is retried through its original Task
      Then the replayed impact Task exposes the same result
      And "source" has one impact fact and one successful command lifecycle

    Scenario: Two analyzers race to publish the initial surface
      Given impact ChangeSet "RACE" has these projected Candidate checkpoints:
        | role   | candidate_id     | repository | head | path        | observes_path |
        | source | CAN-CUC-IMP-RACE | billing    | b    | lib/race.rb | no            |
      When two analyzers concurrently submit different initial surfaces for "source"
      Then one impact Task succeeds and the other reports an already-recorded surface
      And only the winning impact command has target facts

  Rule: Malformed evidence never allocates a Task

    Scenario: An empty semantic surface is rejected synchronously
      Given impact ChangeSet "INVALID" has these projected Candidate checkpoints:
        | role   | candidate_id        | repository | head | path           | observes_path |
        | source | CAN-CUC-IMP-INVALID | billing    | b    | lib/invalid.rb | no            |
      When the analyzer attempts to submit an empty impact surface for "source"
      Then the impact request is rejected before Task allocation
      And "source" has no impact facts or command lifecycle
