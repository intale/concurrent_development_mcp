# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationObligationContextV1 < Value
      attribute :source_creation, Events::VerificationObligationCreatedV1
      attribute :source_creation_event, Types.Instance(PgEventstore::Event)
      attribute? :target_creation_event, EventReference.optional.default(nil)
      attribute :target_stream, StreamReference
      attribute :obligation_id, Types::UuidV7
      attribute :change_set_id, Types::UuidV7
      attribute :source_candidate, CandidateSubjectMigrationV1
      attribute :target_candidate, CandidateSubjectMigrationV1
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :natural_key_marker, Types::ResourceMarker

      def source_creation_reference
        EventReference.new(
          event_id: source_creation_event.id,
          type: source_creation_event.type,
          stream_context: source_creation_event.stream.context,
          stream_name: source_creation_event.stream.stream_name,
          stream_id: source_creation_event.stream.stream_id,
          stream_revision: source_creation_event.stream_revision
        )
      end

      def scope_markers
        source = source_candidate.target_subject
        target = target_candidate.target_subject
        [
          "verification-obligation:#{obligation_id}",
          "verification-obligation-kind:#{source_creation.kind}",
          "change-set:#{change_set_id}",
          "source-candidate:#{source.candidate_id}",
          "target-candidate:#{target.candidate_id}",
          "candidate:#{source.candidate_id}",
          "candidate:#{target.candidate_id}",
          "work-item:#{source.work_item_id}",
          "work-item:#{target.work_item_id}",
          "repository:#{source.repository_id}",
          "repository:#{target.repository_id}",
          "enforcement:#{source_creation.enforcement}",
          "decision:#{policy.head.decision_id}"
        ].freeze
      end

      def markers(status: nil)
        values = scope_markers
        values += [ "verification-obligation-status:#{status}" ] if status
        values.freeze
      end
    end
  end
end
