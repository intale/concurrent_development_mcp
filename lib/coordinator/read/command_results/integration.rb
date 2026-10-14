# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Integration
      TOOLS = %w[merge_snapshot_register merge_verification_submit merge_authorization_request merge_observation_record
        release_set_prepare release_repository_integration_record release_verification_record release_activation_record release_compensation_complete].freeze

      def initialize(facts:)
        @facts = facts
      end

      def call(source)
        case source.tool_name
        when "merge_snapshot_register" then snapshot(source)
        when "merge_verification_submit" then verification(source)
        when "merge_authorization_request" then authorization(source)
        when "merge_observation_record" then observation(source)
        when "release_set_prepare" then preparation(source)
        when "release_repository_integration_record" then repository_integration(source)
        when "release_verification_record" then release_verification(source)
        when "release_activation_record" then activation(source)
        when "release_compensation_complete" then compensation(source)
        end
      end

      private

      def snapshot(source)
        event = source.event("MergeSnapshotRegistered")
        result(source, "Attributed external merge snapshot registered.",
          source.values(:merge_snapshot_id, :repository_id, :target_branch, :target_base_commit_oid, :ordered_candidates, :merge_commit_oid).merge(
            object_format: source.input.fetch(:target_base_commit_oid).length == 40 ? "sha1" : "sha256",
            snapshot_digest: event.metadata.fetch("snapshot_digest"), evidence_status: "attributed_unverified",
            snapshot_event: source.reference(event), registered_at: source.timestamp(event)
          ), "merge_snapshot_get", :merge_snapshot_id)
      end

      def verification(source)
        event = source.event("MergeSnapshotVerificationSubmitted")
        fact = source.data(event)
        assessment = fact.fetch(:assessment)
        status = assessment.fetch(:conclusion) == "passed" ? "unverified" : assessment.fetch(:conclusion)
        result(source, "Combined-test evidence accepted; exact merge snapshot remains unverified.", fact.slice(:merge_snapshot_id, :verification_id).merge(
          evidence_kind: assessment.fetch(:evidence_kind), conclusion: assessment.fetch(:conclusion), status:,
          verification_input_digest: event.metadata.fetch("verification_input_digest"), submitted_event: source.reference(event),
          verified_event: nil, submitted_at: source.timestamp(event)
        ), "merge_snapshot_get", :merge_snapshot_id)
      end

      def authorization(source)
        event = source.events("MergeAuthorizationGranted", "MergeAuthorizationDenied").first
        outcome = event.type == "MergeAuthorizationGranted" ? "granted" : "denied"
        fact = source.data(event)
        summary = outcome == "granted" ?
          "Recorded evidence satisfies merge-authorization policy; the external merge has not been performed." :
          "Merge authorization was denied from the exact recorded evidence; the external merge was not performed."
        result(source, summary, fact.slice(:authorization_id, :merge_snapshot_id).merge(
          outcome:, decision_digest: event.metadata.fetch("decision_digest"), decision_event: source.reference(event),
          **fact.fetch(:evaluation).slice(:reasons, :obligations, :work_item_progress), decided_at: source.timestamp(event)
        ), "merge_snapshot_get", :merge_snapshot_id)
      end

      def observation(source)
        event = source.event("MergeObserved")
        result(source, "Attributed external merge transition recorded; the coordinator did not perform or verify it.",
          source.values(:merge_snapshot_id, :authorization_event, :authorization_decision_digest, :repository_id, :target_branch,
            :object_format, :target_before_commit_oid, :target_after_commit_oid, :observed_at).merge(
            observation_digest: event.metadata.fetch("observation_digest"), evidence_status: "attributed_unverified",
            observation_event: source.reference(event), recorded_at: source.timestamp(event)
          ), "merge_snapshot_get", :merge_snapshot_id)
      end

      def preparation(source)
        event = source.event("ReleaseSetPrepared")
        members = source.events("ReleaseSetMemberAdded").map do |member|
          fact = source.data(member)
          fact.slice(:repository_id, :merge_snapshot_id, :ordered_candidate_ids, :authorization_event).merge(position: fact.fetch(:member_position))
        end
        result(source, "Immutable ordered ReleaseSet prepared from exact current authorization evidence.", source.values(:release_set_id).merge(
          change_set_id: source.fact("ReleaseSetCreated").fetch(:change_set_id), ordered_members: members,
          release_digest: event.metadata.fetch("release_digest"), policy_version: "release-set-preparation/v1",
          prepared_event: source.reference(event), prepared_at: source.timestamp(event)
        ), "release_set_get", :release_set_id)
      end

      def repository_integration(source)
        event = source.event("RepositoryIntegrationRecorded")
        fact = source.data(event)
        summary = fact.fetch(:outcome) == "integrated" ?
          "Attributed external repository integration recorded for the immutable ReleaseSet member." :
          "Attributed external repository integration failure recorded; the ReleaseSet may require retry or compensation."
        result(source, summary, fact.slice(:release_set_id, :change_set_id, :repository_id, :member_position, :attempt_id, :attempt_number, :outcome).merge(
          integration_digest: event.metadata.fetch("integration_digest"), evidence_status: "attributed_unverified",
          integration_event: source.reference(event), recorded_at: source.timestamp(event)
        ), "release_set_get", :release_set_id)
      end

      def release_verification(source)
        event = source.event("ReleaseSetVerificationRecorded")
        fact = source.data(event)
        outcome = fact.fetch(:evidence).fetch(:outcome)
        summary = outcome == "passed" ? "Attributed composite verification passed for the exact integrated ReleaseSet." :
          "Attributed composite verification failure recorded for the exact integrated ReleaseSet."
        result(source, summary, fact.slice(:release_set_id, :change_set_id, :attempt_number).merge(
          outcome:, integration_events: source.events("ReleaseSetIntegrationLinked").map { source.data(_1).fetch(:integration_event) },
          verification_digest: event.metadata.fetch("verification_digest"), evidence_status: "attributed_unverified",
          verification_event: source.reference(event), recorded_at: source.timestamp(event)
        ), "release_set_get", :release_set_id)
      end

      def activation(source)
        event = source.event("ReleaseSetActivated")
        result(source, "Attributed external ReleaseSet activation recorded; lifecycle completion is asynchronous.",
          source.values(:release_set_id, :verification_event, :verification_digest).merge(change_set_id: event.data.fetch("change_set_id"),
            activation_digest: event.metadata.fetch("activation_digest"), evidence_status: "attributed_unverified",
            activation_event: source.reference(event), recorded_at: source.timestamp(event)
          ), "release_set_get", :release_set_id)
      end

      def compensation(source)
        event = source.event("ReleaseSetCompleted")
        outcome = source.event("ReleaseSetOutcomeRecorded")
        creation = @facts.first(:release_set, source.input.fetch(:release_set_id), "ReleaseSetCreated")
        result(source, "Attributed external compensation evidence completed the ReleaseSet lifecycle.", source.values(:release_set_id).merge(
          change_set_id: creation.data.fetch("change_set_id"), outcome: outcome.data.fetch("outcome"),
          source_event: source.input.fetch(:compensation_request_event), completion_digest: outcome.metadata.fetch("completion_digest"),
          completion_event: source.reference(event), completed_at: source.timestamp(event)
        ), "release_set_get", :release_set_id)
      end

      def result(source, summary, data, tool, key)
        source.presentation(summary, data, next_actions: [ source.action(tool, **source.values(key)) ])
      end
    end
  end
end
