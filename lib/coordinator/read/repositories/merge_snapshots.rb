# frozen_string_literal: true

module Coordinator::Read
  module Repositories
    class MergeSnapshots
      def initialize(authorizations: MergeAuthorizations.new)
        @authorizations = authorizations
      end

      def fetch(merge_snapshot_id)
        record = Coordinator::Read::MergeSnapshot.find_by(merge_snapshot_id:)
        record && build_view(record)
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
