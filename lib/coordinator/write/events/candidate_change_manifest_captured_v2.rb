# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateChangeManifestCapturedV2 < Base
      File = Candidates::ManifestFileV1

      contract type: "CandidateChangeManifestCaptured", version: 2

      attribute :candidate_id, Types::Identifier
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :files,
                Types::Array.of(File).constrained(
                  min_size: 1,
                  max_size: Types::CANDIDATE_MANIFEST_MAXIMUM_FILE_COUNT
                )
    end
  end
end
