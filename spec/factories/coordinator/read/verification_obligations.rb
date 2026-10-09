# frozen_string_literal: true

FactoryBot.define do
  factory :coordinator_read_verification_obligation,
          class: "Coordinator::Read::VerificationObligation" do
    transient do
      required_evidence { %w[combined_tests] }
    end

    sequence(:obligation_id) { "OBL-factory-#{_1}" }
    sequence(:change_set_id) { "CS-factory-obligation-#{_1}" }
    source_candidate_id { "CAN-source-#{obligation_id}" }
    target_candidate_id { "CAN-target-#{obligation_id}" }
    source_work_item_id { "W-source-#{obligation_id}" }
    target_work_item_id { "W-target-#{obligation_id}" }
    source_repository_id { "018f0f4d-4e45-7abc-8def-000000000081" }
    target_repository_id { "018f0f4d-4e45-7abc-8def-000000000082" }
    kind { "candidate_compatibility" }
    status { "open" }
    enforcement { "merge_gate" }
    obligation do
      reference = ->(type, stream_name, stream_id, revision) do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => type,
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => stream_name,
          "stream_id" => stream_id,
          "stream_revision" => revision
        }
      end
      subject = ->(candidate_id, work_item_id, repository_id, suffix) do
        surface_id = SecureRandom.uuid_v7
        {
          "candidate_id" => candidate_id,
          "change_set_id" => change_set_id,
          "work_item_id" => work_item_id,
          "attempt_id" => "A-#{suffix}-#{obligation_id}",
          "repository_id" => repository_id,
          "target_branch" => "main",
          "object_format" => "sha1",
          "base_commit_oid" => "a" * 40,
          "head_commit_oid" => suffix == "source" ? "b" * 40 : "c" * 40,
          "manifest_digest" => "sha256:#{suffix == 'source' ? 'd' * 64 : 'e' * 64}",
          "build_context_digest" => nil,
          "surface_digest" => "sha256:#{suffix == 'source' ? 'f' * 64 : '1' * 64}",
          "candidate_event" => reference.call("CandidateSubmitted", "Candidate", candidate_id, 8),
          "manifest_event" => reference.call("CandidateChangeManifestCaptured", "Candidate", candidate_id, 7),
          "build_context_event" => nil,
          "surface_event" => reference.call("CandidateImpactSurfaceDerived", "CandidateImpactSurface", surface_id, 0),
          "registration_event" => reference.call("CandidateImpactSurfaceAssigned", "Candidate", candidate_id, 9)
        }
      end
      partition = {
        "partition_id" => "changeset:#{change_set_id}:candidate",
        "topic_root" => "candidate",
        "anchor_kind" => "changeset",
        "anchor_id" => change_set_id
      }
      decision_id = "D-policy-#{obligation_id}"
      decision_event = reference.call("DecisionActivated", "Decision", decision_id, 1).merge(
        "stream_context" => "HumanGuidance"
      )
      head = { "decision_id" => decision_id, "decision_revision" => 1, "event" => decision_event }
      partition_event = reference.call(
        "DecisionAddedToPartition",
        "DecisionPartition",
        partition.fetch("partition_id"),
        0
      ).merge("stream_context" => "HumanGuidance")
      source = subject.call(source_candidate_id, source_work_item_id, source_repository_id, "source")
      target = subject.call(target_candidate_id, target_work_item_id, target_repository_id, "target")
      {
        "obligation_id" => obligation_id,
        "kind" => kind,
        "change_set_id" => change_set_id,
        "source_candidate" => source,
        "target_candidate" => target,
        "reasons" => [
          {
            "kind" => "semantic_key_match",
            "matches" => [ "contract:payments:v1" ],
            "source_evidence" => source.fetch("surface_event"),
            "target_evidence" => target.fetch("surface_event")
          }
        ],
        "required_evidence" => required_evidence,
        "enforcement" => enforcement,
        "policy" => {
          "partition_event" => partition_event,
          "partition" => partition,
          "head" => head,
          "definition_digest" => "sha256:#{'2' * 64}",
          "change_set_id" => change_set_id,
          "required_evidence" => required_evidence,
          "enforcement" => enforcement,
          "valid_from" => "2026-08-30T12:00:00.000000Z"
        },
        "validity_input_digest" => "sha256:#{'3' * 64}",
        "rule_version" => "candidate-compatibility-obligation/v1",
        "created_at" => "2026-08-30T12:00:00.000000Z"
      }
    end
    event do
      {
        "event_id" => SecureRandom.uuid_v7,
        "type" => "VerificationObligationCreated",
        "stream_context" => "DevelopmentIntegration",
        "stream_name" => "VerificationObligation",
        "stream_id" => obligation_id,
        "stream_revision" => 0
      }
    end
    actor { { "kind" => "system", "id" => "candidate-impact-obligation-policy", "authenticated" => false } }
    markers { [ "verification-obligation:#{obligation_id}" ] }
    metadata { { "schema_version" => 2 } }
    sequence(:event_global_position, 1_200)
    created_at_domain { Time.utc(2026, 8, 30, 12) }
    created_at_store { Time.utc(2026, 8, 30, 12, 0, 1) }
    evidence_count { 0 }
    passed_evidence_kinds { [] }
    missing_evidence_kinds { required_evidence }

    trait :claimed do
      claim_id { SecureRandom.uuid_v7 }
      claimant_id { "factory-agent" }
      claim_fencing_token { 1 }
      claim_claimed_at_domain { Time.utc(2026, 8, 30, 12, 1) }
      claim_expires_at_domain { Time.utc(2026, 8, 30, 12, 6) }
      claim do
        {
          "obligation_id" => obligation_id,
          "claim_id" => claim_id,
          "claimant_id" => claimant_id,
          "fencing_token" => claim_fencing_token,
          "expires_at" => claim_expires_at_domain.iso8601(6)
        }
      end
      claim_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "VerificationObligationClaimed",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "VerificationObligation",
          "stream_id" => obligation_id,
          "stream_revision" => 1
        }
      end
      claim_actor { { "kind" => "agent", "id" => claimant_id, "authenticated" => false } }
      claim_markers { markers }
      claim_metadata { { "schema_version" => 2 } }
      claim_event_global_position { event_global_position + 1 }
      claim_stream_revision { 1 }
      claim_created_at_store { Time.utc(2026, 8, 30, 12, 1, 1) }
    end

    trait :satisfied do
      status { "satisfied" }
      evidence_count { 1 }
      passed_evidence_kinds { required_evidence }
      missing_evidence_kinds { [] }
      terminal_outcome do
        evidence_id = SecureRandom.uuid_v7
        evidence_event = {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "VerificationEvidenceSubmitted",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "VerificationObligation",
          "stream_id" => obligation_id,
          "stream_revision" => 2
        }
        {
          "obligation_id" => obligation_id,
          "obligation_event" => event,
          "policy" => obligation.fetch("policy"),
          "selected_evidence" => [
            {
              "evidence_kind" => required_evidence.first,
              "evidence_id" => evidence_id,
              "conclusion" => "passed",
              "result_digest" => "sha256:#{'4' * 64}",
              "assessment_input_digest" => "sha256:#{'5' * 64}",
              "event" => evidence_event
            }
          ],
          "outcome_digest" => "sha256:#{'6' * 64}",
          "satisfied_at" => "2026-08-30T12:03:00.000000Z"
        }
      end
      terminal_event do
        {
          "event_id" => SecureRandom.uuid_v7,
          "type" => "VerificationObligationSatisfied",
          "stream_context" => "DevelopmentIntegration",
          "stream_name" => "VerificationObligation",
          "stream_id" => obligation_id,
          "stream_revision" => 3
        }
      end
      terminal_actor { { "kind" => "system", "id" => "verification-outcomes", "authenticated" => false } }
      terminal_markers { markers }
      terminal_metadata { { "schema_version" => 2 } }
      terminal_event_global_position { event_global_position + 3 }
      terminal_stream_revision { 3 }
      terminal_at_domain { Time.utc(2026, 8, 30, 12, 3) }
      terminal_created_at_store { Time.utc(2026, 8, 30, 12, 3, 1) }
    end
  end

  factory :coordinator_read_verification_obligation_evidence_item,
          class: "Coordinator::Read::VerificationObligationEvidenceItem" do
    transient do
      source_obligation { nil }
    end

    evidence_id { SecureRandom.uuid_v7 }
    sequence(:obligation_id) { "OBL-factory-evidence-#{_1}" }
    evidence_kind { "combined_tests" }
    conclusion { "passed" }
    assessment_input_digest { "sha256:#{'5' * 64}" }
    result_digest { "sha256:#{'4' * 64}" }
    submission do
      {
        "obligation_id" => obligation_id,
        "evidence_id" => evidence_id,
        "evidence_kind" => evidence_kind,
        "claim" => source_obligation ? {
          "claim_id" => source_obligation.claim_id,
          "claimant_id" => source_obligation.claimant_id,
          "fencing_token" => source_obligation.claim_fencing_token,
          "claim_event" => source_obligation.claim_event
        } : {
          "claim_id" => SecureRandom.uuid_v7,
          "claimant_id" => "factory-agent",
          "fencing_token" => 1,
          "claim_event" => {
            "event_id" => SecureRandom.uuid_v7,
            "type" => "VerificationObligationClaimed",
            "stream_context" => "DevelopmentIntegration",
            "stream_name" => "VerificationObligation",
            "stream_id" => obligation_id,
            "stream_revision" => 1
          }
        },
        "assessment" => {
          "evidence_kind" => evidence_kind,
          "producer" => { "name" => "factory-suite", "version" => "1.0" },
          "run_id" => "run-factory",
          "test_suite_digest" => "sha256:#{'7' * 64}",
          "environment_digest" => "sha256:#{'8' * 64}",
          "dependency_graph_digest" => "sha256:#{'9' * 64}",
          "result_digest" => result_digest,
          "conclusion" => conclusion,
          "findings" => [],
          "produced_at" => "2026-08-30T12:02:00.000000Z"
        }
      }
    end
    event_id { SecureRandom.uuid_v7 }
    event do
      {
        "event_id" => event_id,
        "type" => "VerificationEvidenceSubmitted",
        "stream_context" => "DevelopmentIntegration",
        "stream_name" => "VerificationObligation",
        "stream_id" => obligation_id,
        "stream_revision" => 2
      }
    end
    actor { { "kind" => "agent", "id" => "factory-agent", "authenticated" => false } }
    markers { [ "verification-obligation:#{obligation_id}" ] }
    metadata do
      {
        "schema_version" => 2,
        "policy_version" => "compatibility-assessment/v2",
        "obligation_validity_input_digest" => "sha256:#{'3' * 64}",
        "assessment_input_digest" => assessment_input_digest
      }
    end
    sequence(:event_global_position, 1_300)
    stream_revision { 2 }
    produced_at_domain { Time.utc(2026, 8, 30, 12, 2) }
    submitted_at_domain { Time.utc(2026, 8, 30, 12, 2) }
    created_at_store { Time.utc(2026, 8, 30, 12, 2, 1) }
  end
end
