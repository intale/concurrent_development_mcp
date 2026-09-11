@verification_evidence_outcomes
Feature: Agents submit attributed compatibility evidence through checkpointed Tasks
  Evidence reports exact external inputs and conclusions without claiming that the coordinator ran verification.
  Authoritative commands decide from event facts while latest-available obligation views may lag and converge.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Accepted evidence remains attributed and may complete the obligation

    Scenario: Two passed required assessments move an obligation from partial to satisfied
      Given agent "agent-blue" actively claims Rails verification obligation "EVIDENCE-SATISFIED"
      When the claimant submits "passed" "combined_tests" evidence as command "cmd-cuc-evidence-tests"
      Then the evidence Task completes with obligation status "open"
      And one attributed evidence fact and no terminal fact are durable
      When the claimant submits "passed" "contract_compatibility_review" evidence as command "cmd-cuc-evidence-contract"
      Then the evidence Task completes with obligation status "open"
      And two attributed evidence facts and one satisfied fact are durable
      And the final evidence, outcome, command terminal, and Task carry exact tracing

    Scenario: Failed required evidence immediately fails the obligation
      Given agent "agent-blue" actively claims Rails verification obligation "EVIDENCE-FAILED"
      When the claimant submits "failed" "combined_tests" evidence as command "cmd-cuc-evidence-failed"
      Then the evidence Task completes with obligation status "open"
      And one attributed evidence fact and one failed fact are durable
      And the evidence result remains an attributed report rather than an execution claim

    Scenario: Inconclusive and not-applicable reports remain nonterminal
      Given agent "agent-blue" actively claims Rails verification obligation "EVIDENCE-NONTERMINAL"
      When the claimant submits "inconclusive" "combined_tests" evidence as command "cmd-cuc-evidence-inconclusive"
      And the claimant submits "not_applicable" "contract_compatibility_review" evidence as command "cmd-cuc-evidence-not-applicable"
      Then both nonterminal evidence Tasks complete with an open obligation
      And two explanatory evidence facts and no terminal fact are durable

  Rule: Claim fences and assessment identity prevent stale or duplicate work

    Scenario: Reclaiming after expiry rejects the predecessor fence
      Given agent "agent-blue" claims Rails verification obligation "EVIDENCE-FENCE" for 30 seconds
      When agent "agent-green" reclaims the obligation after expiry
      And the prior claimant submits evidence with the stale fence
      Then the stale evidence Task reports "verification_obligation_claim_stale" without target facts

    Scenario: Command replay returns the result while a new command cannot duplicate its assessment
      Given agent "agent-blue" actively claims Rails verification obligation "EVIDENCE-REPLAY"
      When the claimant submits "inconclusive" "combined_tests" evidence as command "cmd-cuc-evidence-replay"
      And the exact evidence command is submitted again
      Then both evidence responses expose the same Task result and one evidence fact
      When the same assessment is submitted as new command "cmd-cuc-evidence-duplicate"
      Then the duplicate evidence Task reports "verification_evidence_already_submitted" with a rejected command lifecycle

  Rule: Concurrent commands serialize and available reads converge without a freshness gate

    Scenario: Concurrent final evidence produces exactly one satisfaction outcome
      Given agent "agent-blue" actively claims Rails verification obligation "EVIDENCE-RACE"
      When the claimant executes both required evidence Tasks concurrently
      Then both evidence Tasks succeed with open submission results
      And exactly two evidence facts and one satisfied fact are durable

    Scenario: An older open view remains available until evidence and outcome projection converge
      Given agent "agent-blue" actively claims Rails verification obligation "EVIDENCE-VIEW" with its claim available
      When both passed assessments commit without projecting their evidence
      Then the available view still reports open with no observed evidence
      When the evidence and outcome reach the read side after a subscription restart
      Then the available view reports satisfied with complete attributed evidence
