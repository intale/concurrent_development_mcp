@candidate_impact_obligation
Feature: Candidate impact policy creates exact external-verification obligations
  Agents coordinate Rails upgrade Candidates from attributed impact evidence and available obligation views.
  A gate records required external work; it never claims incompatibility, verification, or merge safety.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Disabled and advisory policy never become an obligation gate

    Scenario Outline: Non-gating policy preserves potential impact without creating an obligation
      Given Rails 4 to Rails 5 Candidate pair "<case>" has registered attributed impact surfaces
      When the user activates "<level>" Candidate impact policy through guidance Tasks
      And the policy reaction is delivered twice
      Then no Candidate compatibility obligation is durable
      And the available Candidate impact policy is "<level>" without a gate

      Examples:
        | case     | level    |
        | DISABLED | disabled |
        | ADVISORY | advisory |

  Rule: Reciprocal Saga sources repair either commit order and converge duplicate delivery

    Scenario: A verification gate activated after both surfaces creates one exact open obligation
      Given Rails 4 to Rails 5 Candidate pair "POLICY-LATE" has registered attributed impact surfaces
      When the user activates "verification_gate" Candidate impact policy through guidance Tasks
      And the policy reaction is delivered twice
      Then one exact open Rails obligation is durable under "verification_gate"
      And the obligation query stays available and empty before projection
      When the obligation creation reaches the read side twice
      Then the agent sees one exact open Rails obligation under "verification_gate"

    Scenario: A Candidate surface registered after a merge gate repairs the earlier empty sweep
      Given Rails 4 to Rails 5 Candidate checkpoints "SURFACE-LATE" exist without impact surfaces
      When the user activates "merge_gate" Candidate impact policy through guidance Tasks
      And the empty policy sweep is delivered twice
      And both Rails impact surfaces register after the policy with duplicate delivery
      Then one exact open Rails obligation is durable under "merge_gate"
      When the obligation creation reaches the read side twice
      Then the agent sees one exact open Rails obligation under "merge_gate"
