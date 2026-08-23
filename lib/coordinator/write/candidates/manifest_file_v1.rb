# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ManifestFileV1 < Value
      attribute :status, Types::CandidateManifestStatus
      attribute :old_path, Types::ResourcePath.optional
      attribute :new_path, Types::ResourcePath.optional
      attribute :old_blob_oid, Types::GitOid.optional
      attribute :new_blob_oid, Types::GitOid.optional
      attribute :old_mode, Types::CandidateGitFileMode.optional
      attribute :new_mode, Types::CandidateGitFileMode.optional
    end
  end
end
