@event-contract
Feature: Guidance interpretation
  Guidance remains attributed evidence until explicit interpretation and adjudication commands succeed.

  Background:
    Given an MCP agent supports checkpointed Tasks

  Rule: Deliberately submitted guidance remains attributed evidence until a later decision

    @CDM-GUIDANCE-001 @stale-view
    Scenario: Direct guidance becomes available without activating policy
      When agent "host-1" records direct guidance "Do not use Redis in billing." as message "M-CUC-GDN-1" in conversation "C-CUC-GDN-1"
      Then the guidance Task records one evidence-only fact
      And the available guidance query honestly reports that message as not observed
      When the guidance reaches the read side
      Then the available guidance preserves its text and unauthenticated attribution without a freshness claim

    @CDM-GUIDANCE-002
    Scenario: A globally reused forwarded message identity is denied
      When agent "host-1" forwards guidance "Keep tests on RSpec." as message "M-CUC-GDN-2" in conversation "C-CUC-GDN-2"
      And agent "host-2" tries to record the same message in conversation "C-CUC-GDN-OTHER"
      Then the second guidance Task completes with message identity denial
      And only the first Conversation owns the forwarded evidence

  Rule: Classifier interpretations remain concurrent atomic proposals until adjudication

    @CDM-INTERPRETATION-001 @concurrency @stale-view
    Scenario: Two classifiers propose different readings of one guidance message
      Given guidance "Use RSpec." is durably recorded as message "M-CUC-GDN-3" in conversation "C-CUC-GDN-3"
      When two classifiers independently propose atomic interpretations through Tasks
      Then both proposal Tasks complete while no policy is activated
      And the hard proposal and its clarification are persisted atomically
      And the available interpretation query honestly reports no proposals before projection
      When the interpretation proposals reach the read side
      Then the available query lists both proposal-only interpretations without a freshness claim

  Rule: Adjudication serializes competing interpretations without activating policy

    @CDM-INTERPRETATION-002 @concurrency @stale-view
    Scenario: Concurrent acceptance of one canonical slot has one winner
      Given guidance "Use RSpec." is durably recorded as message "M-CUC-GDN-4" in conversation "C-CUC-GDN-4"
      When two classifiers independently propose atomic interpretations through Tasks
      And the interpretation proposals reach the read side
      When the host concurrently accepts both interpretation proposals through Tasks
      Then one acceptance Task succeeds and the other reports a slot conflict
      And the projected interpretation view remains available at its previous lifecycle state
      When the interpretation adjudications reach the read side
      Then exactly one proposal is accepted for later activation without activating policy

    @CDM-INTERPRETATION-003 @stale-view
    Scenario: Clarification remains nonterminal and can be followed by rejection
      Given guidance "Use RSpec." is durably recorded as message "M-CUC-GDN-5" in conversation "C-CUC-GDN-5"
      When two classifiers independently propose atomic interpretations through Tasks
      And the interpretation proposals reach the read side
      When the host requests clarification for interpretation "I-CUC-A" through a Task
      Then the clarification Task succeeds while the prior view remains available
      When the interpretation adjudications reach the read side
      Then the available interpretation exposes a nonterminal clarification
      When the host rejects interpretation "I-CUC-A" through a Task
      Then the rejection Task succeeds while the clarification view remains available
      When the interpretation adjudications reach the read side
      Then the available interpretation is rejected without activating policy
