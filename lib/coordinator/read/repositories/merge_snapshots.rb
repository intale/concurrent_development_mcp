# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class MergeSnapshots
      def fetch(merge_snapshot_id)
        record = Coordinator::Read::MergeSnapshot.find_by(merge_snapshot_id:)
        record && build_view(record)
      end

      def store(event:, snapshot:)
        Coordinator::Read::MergeSnapshot.create!(
          merge_snapshot_id: snapshot.merge_snapshot_id,
          repository_id: snapshot.repository_id,
          target_branch: snapshot.target_branch,
          object_format: snapshot.object_format,
          target_base_commit_oid: snapshot.target_base_commit_oid,
          ordered_candidates: snapshot.ordered_candidates.map(&:to_h),
          merge_commit_oid: snapshot.merge_commit_oid,
          producer: snapshot.producer.to_h,
          run_id: snapshot.run_id,
          produced_at_domain: snapshot.produced_at,
          snapshot_digest: snapshot.snapshot_digest,
          policy_version: snapshot.policy_version,
          evidence_status: snapshot.evidence_status,
          registered_at_domain: snapshot.registered_at,
          registered_event: event_reference(event).to_h,
          registered_actor: actor(event).to_h,
          registered_markers: event.markers,
          registered_metadata: event.metadata,
          registered_causation_id: event.causation_id,
          registered_correlation_id: event.correlation_id,
          registered_global_position: event.global_position,
          registered_at_store: event.created_at
        )
      end

      def record_submission(event:, submission:)
        record = Coordinator::Read::MergeSnapshot.find_by!(
          merge_snapshot_id: submission.merge_snapshot_id
        )
        view = MergeSnapshotVerificationSubmissionViewV1.new(
          verification_id: submission.verification_id,
          policy_version: submission.policy_version,
          assessment: submission.assessment,
          verification_input_digest: submission.verification_input_digest,
          submitted_at: submission.submitted_at,
          source: event_source(event, occurred_at: submission.submitted_at)
        )
        status = submission.assessment.conclusion == "passed" ? "unverified" : submission.assessment.conclusion
        record.update!(
          verification_status: status,
          verification_policy_version: submission.policy_version,
          verification_submissions: [ *record.verification_submissions, view.to_h ]
        )
      end

      def record_verified(event:, verified:)
        record = Coordinator::Read::MergeSnapshot.find_by!(
          merge_snapshot_id: verified.merge_snapshot_id
        )
        view = MergeSnapshotVerifiedViewV1.new(
          policy_version: verified.policy_version,
          selected_verification: verified.selected_verification,
          verification_digest: verified.verification_digest,
          verified_at: verified.verified_at,
          source: event_source(event, occurred_at: verified.verified_at)
        )
        record.update!(
          verification_status: "verified",
          verification_policy_version: verified.policy_version,
          verified_decision: view.to_h
        )
      end

      private

      def build_view(record)
        MergeSnapshotViewV1.new(
          merge_snapshot_id: record.merge_snapshot_id,
          repository_id: record.repository_id,
          target_branch: record.target_branch,
          object_format: record.object_format,
          target_base_commit_oid: record.target_base_commit_oid,
          ordered_candidates: record.ordered_candidates.map do |candidate|
            Coordinator::Write::MergeSnapshots::CandidateMemberV1.new(symbolize(candidate))
          end,
          merge_commit_oid: record.merge_commit_oid,
          producer: Coordinator::Write::MergeSnapshots::ProducerV1.new(symbolize(record.producer)),
          run_id: record.run_id,
          produced_at: record.produced_at_domain.utc.iso8601(6),
          snapshot_digest: record.snapshot_digest,
          policy_version: record.policy_version,
          evidence_status: record.evidence_status,
          registered: registration_source_evidence(record),
          verification: verification_view(record)
        )
      end

      def registration_source_evidence(record)
        MergeSnapshotSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(symbolize(record.registered_event)),
          actor: AttributedActorV1.new(symbolize(record.registered_actor)),
          markers: record.registered_markers,
          metadata: record.registered_metadata,
          global_position: record.registered_global_position,
          occurred_at: record.registered_at_domain.utc.iso8601(6),
          persisted_at: record.registered_at_store.utc.iso8601(6),
          causation_id: record.registered_causation_id,
          correlation_id: record.registered_correlation_id
        )
      end


      def verification_view(record)
        MergeSnapshotVerificationViewV1.new(
          status: record.verification_status,
          policy_version: record.verification_policy_version,
          submissions: record.verification_submissions.map do |submission|
            attributes = symbolize(submission)
            MergeSnapshotVerificationSubmissionViewV1.new(
              verification_id: attributes.fetch(:verification_id),
              policy_version: attributes.fetch(:policy_version),
              assessment: Coordinator::Write::MergeSnapshotVerifications::AssessmentV1.new(
                attributes.fetch(:assessment)
              ),
              verification_input_digest: attributes.fetch(:verification_input_digest),
              submitted_at: attributes.fetch(:submitted_at),
              source: source_from_hash(attributes.fetch(:source))
            )
          end,
          verified: verified_view(record.verified_decision)
        )
      end

      def verified_view(value)
        return unless value

        attributes = symbolize(value)
        MergeSnapshotVerifiedViewV1.new(
          policy_version: attributes.fetch(:policy_version),
          selected_verification:
            Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
              attributes.fetch(:selected_verification)
            ),
          verification_digest: attributes.fetch(:verification_digest),
          verified_at: attributes.fetch(:verified_at),
          source: source_from_hash(attributes.fetch(:source))
        )
      end

      def event_source(event, occurred_at:)
        MergeSnapshotSourceEvidenceV1.new(
          event: event_reference(event),
          actor: actor(event),
          markers: event.markers,
          metadata: event.metadata,
          global_position: event.global_position,
          occurred_at:,
          persisted_at: event.created_at.utc.iso8601(6),
          causation_id: event.causation_id,
          correlation_id: event.correlation_id
        )
      end

      def source_from_hash(value)
        attributes = symbolize(value)
        MergeSnapshotSourceEvidenceV1.new(
          event: Coordinator::Write::EventReference.new(attributes.fetch(:event)),
          actor: AttributedActorV1.new(attributes.fetch(:actor)),
          markers: attributes.fetch(:markers),
          metadata: attributes.fetch(:metadata),
          global_position: attributes.fetch(:global_position),
          occurred_at: attributes.fetch(:occurred_at),
          persisted_at: attributes.fetch(:persisted_at),
          causation_id: attributes.fetch(:causation_id),
          correlation_id: attributes.fetch(:correlation_id)
        )
      end

      def actor(event)
        AttributedActorV1.new(
          kind: event.metadata.fetch("actor_kind"),
          id: event.metadata.fetch("actor_id"),
          authenticated: false
        )
      end

      def event_reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def symbolize(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, symbolize(nested) ] }
        when Array then value.map { symbolize(_1) }
        else value
        end
      end
    end
  end
end
