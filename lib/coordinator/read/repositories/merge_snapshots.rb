# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class MergeSnapshots
      include EventTimestamped

      def initialize(authorizations: MergeAuthorizations.new)
        @authorizations = authorizations
      end

      def fetch(merge_snapshot_id)
        record = Coordinator::Read::MergeSnapshot.find_by(merge_snapshot_id:)
        record && build_view(record)
      end

      def store(event:, snapshot:)
        create_from_event(Coordinator::Read::MergeSnapshot, event:, attributes: {
          merge_snapshot_id: snapshot.merge_snapshot_id,
          repository_id: snapshot.repository_id,
          target_branch: snapshot.target_branch,
          object_format: snapshot.object_format,
          target_base_commit_oid: snapshot.target_base_commit_oid,
          ordered_candidates: snapshot.ordered_candidates.map(&:to_h),
          merge_commit_oid: snapshot.merge_commit_oid,
          producer: snapshot.producer,
          run_id: snapshot.run_id,
          produced_at_domain: snapshot.produced_at,
          snapshot_digest: snapshot.snapshot_digest,
          policy_version: snapshot.policy_version,
          evidence_status: snapshot.evidence_status,
          registered_at_domain: event.created_at,
          registered_event: event_reference(event).to_h,
          registered_actor: actor(event).to_h,
          registered_markers: event.markers,
          registered_metadata: event.metadata,
          registered_causation_id: event.causation_id,
          registered_correlation_id: event.correlation_id,
          registered_global_position: event.global_position,
          registered_at_store: event.created_at
        })
      end

      def record_submission(event:, submission:)
        record = Coordinator::Read::MergeSnapshot.find_by!(
          merge_snapshot_id: submission.merge_snapshot_id
        )
        view = MergeSnapshotVerificationSubmissionViewV1.new(
          verification_id: submission.verification_id,
          policy_version: event.metadata.fetch("policy_version"),
          assessment: submission.assessment,
          verification_input_digest: event.metadata.fetch("verification_input_digest"),
          submitted_at: event.created_at.utc.iso8601(6),
          source: event_source(event)
        )
        status = submission.assessment.conclusion == "passed" ? "unverified" : submission.assessment.conclusion
        save_from_event(record, event:, attributes: {
          verification_status: status,
          verification_policy_version: event.metadata.fetch("policy_version"),
          verification_submissions: [ *record.verification_submissions, view.to_h ]
        })
      end

      def record_selection(event:, selection:)
        record = Coordinator::Read::MergeSnapshot.find_by!(
          merge_snapshot_id: selection.merge_snapshot_id
        )
        save_from_event(record, event:, attributes: {
          verified_decision: {
            verification_id: selection.verification_id,
            selected_event: event_reference(event).to_h
          }
        })
      end

      def record_verified(event:, verified:)
        record = Coordinator::Read::MergeSnapshot.find_by!(
          merge_snapshot_id: verified.merge_snapshot_id
        )
        selection = symbolize(record.verified_decision || {})
        verification_id = selection.fetch(:verification_id)
        submission = record.verification_submissions
          .map { symbolize(_1) }
          .find { _1.fetch(:verification_id) == verification_id }
        raise ProjectionStateError, "Selected merge verification was not projected" unless submission

        assessment = Coordinator::Write::MergeSnapshotVerifications::AssessmentV1.new(
          submission.fetch(:assessment)
        )
        submission_source = source_from_hash(submission.fetch(:source))
        selected = Coordinator::Write::MergeSnapshotVerifications::VerificationDecisionReferenceV1.new(
          verification_id:,
          evidence_kind: assessment.evidence_kind,
          conclusion: assessment.conclusion,
          result_digest: assessment.result_digest,
          verification_input_digest: submission.fetch(:verification_input_digest),
          event: submission_source.event
        )
        view = MergeSnapshotVerifiedViewV1.new(
          policy_version: event.metadata.fetch("policy_version"),
          selected_verification: selected,
          verification_digest: event.metadata.fetch("verification_digest"),
          verified_at: event.created_at.utc.iso8601(6),
          source: event_source(event)
        )
        save_from_event(record, event:, attributes: {
          verification_status: "verified",
          verification_policy_version: event.metadata.fetch("policy_version"),
          verified_decision: view.to_h
        })
      end

      def record_observation(event:, observation:)
        record = Coordinator::Read::MergeSnapshot.find_by!(
          merge_snapshot_id: observation.merge_snapshot_id
        )
        save_from_event(record, event:, attributes: { observation: {
          authorization_event: nil,
          authorization_decision_digest: event.metadata.fetch("authorization_decision_digest"),
          snapshot_binding: observation.snapshot_binding.to_h,
          repository_id: observation.repository_id,
          target_branch: observation.target_branch,
          object_format: observation.object_format,
          target_before_commit_oid: observation.target_before_commit_oid,
          target_after_commit_oid: observation.target_after_commit_oid,
          observer: observation.observer,
          run_id: observation.run_id,
          observed_at: observation.observed_at,
          observation_digest: event.metadata.fetch("observation_digest"),
          policy_version: event.metadata.fetch("policy_version"),
          evidence_status: "attributed_unverified",
          recorded_at: event.created_at.utc.iso8601(6),
          source: event_source(event).to_h
        } })
      end

      def link_observation_authorization(event:, link:)
        record = Coordinator::Read::MergeSnapshot.find_by!(merge_snapshot_id: link.merge_snapshot_id)
        observation = record.observation&.deep_dup
        raise ProjectionStateError, "Merge observation must precede its authorization link" unless observation

        observation["authorization_event"] = link.authorization_event.to_h
        save_from_event(record, event:, attributes: { observation: })
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
          producer: record.producer,
          run_id: record.run_id,
          produced_at: record.produced_at_domain.utc.iso8601(6),
          snapshot_digest: record.snapshot_digest,
          policy_version: record.policy_version,
          evidence_status: record.evidence_status,
          registered: registration_source_evidence(record),
          verification: verification_view(record),
          latest_authorization: @authorizations.latest_for(record.merge_snapshot_id),
          observation: observation_view(record.observation)
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
        return unless attributes[:policy_version]

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

      def observation_view(value)
        return unless value

        attributes = symbolize(value)
        return unless attributes[:authorization_event]

        MergeObservationViewV1.new(
          authorization_event: Coordinator::Write::EventReference.new(
            attributes.fetch(:authorization_event)
          ),
          authorization_decision_digest: attributes.fetch(:authorization_decision_digest),
          snapshot_binding: Coordinator::Write::MergeAuthorizations::SnapshotBindingV1.new(
            attributes.fetch(:snapshot_binding)
          ),
          repository_id: attributes.fetch(:repository_id),
          target_branch: attributes.fetch(:target_branch),
          object_format: attributes.fetch(:object_format),
          target_before_commit_oid: attributes.fetch(:target_before_commit_oid),
          target_after_commit_oid: attributes.fetch(:target_after_commit_oid),
          observer: attributes.fetch(:observer),
          run_id: attributes.fetch(:run_id),
          observed_at: attributes.fetch(:observed_at),
          observation_digest: attributes.fetch(:observation_digest),
          policy_version: attributes.fetch(:policy_version),
          evidence_status: attributes.fetch(:evidence_status),
          recorded_at: attributes.fetch(:recorded_at),
          source: source_from_hash(attributes.fetch(:source))
        )
      end

      def event_source(event)
        MergeSnapshotSourceEvidenceV1.new(
          event: event_reference(event),
          actor: actor(event),
          markers: event.markers,
          metadata: event.metadata,
          global_position: event.global_position,
          occurred_at: event.created_at.utc.iso8601(6),
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
