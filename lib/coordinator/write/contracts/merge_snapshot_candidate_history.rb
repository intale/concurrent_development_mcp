# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class MergeSnapshotCandidateHistory < Dry::Validation::Contract
      params do
        required(:history).value(Types.Instance(MergeSnapshots::CandidateHistoryV1))
      end

      rule(:history) do
        history = value
        candidate = history.candidate
        manifest = history.manifest

        if candidate.nil?
          unless manifest.nil? && history.candidate_event.nil? && history.manifest_event.nil?
            key.failure("must not contain evidence without CandidateSubmitted")
          end
          next
        end

        unless exact_reference?(history.candidate_event, "CandidateSubmitted", candidate.candidate_id, 0)
          key.failure("must preserve the exact CandidateSubmitted reference")
        end
        unless candidate.candidate_id == history.requested.candidate_id
          key.failure("must belong to the requested Candidate ID")
        end

        if manifest
          unless exact_reference?(
            history.manifest_event,
            "CandidateChangeManifestCaptured",
            candidate.candidate_id,
            1
          )
            key.failure("must preserve the exact Candidate manifest reference")
          end
          fields = %i[
            candidate_id repository_id target_branch object_format base_commit_oid head_commit_oid
            manifest_digest
          ]
          unless fields.all? { candidate.public_send(_1) == manifest.public_send(_1) }
            key.failure("CandidateSubmitted and manifest identities must match")
          end
        elsif history.manifest_event
          key.failure("manifest reference must be absent when the manifest is absent")
        end
      end

      private

      def exact_reference?(reference, type, candidate_id, revision)
        reference &&
          reference.type == type &&
          reference.stream_context == "DevelopmentIntegration" &&
          reference.stream_name == "Candidate" &&
          reference.stream_id == candidate_id &&
          reference.stream_revision == revision
      end
    end
  end
end
