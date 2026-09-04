# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateCommitRangeDeclaredV1 < Base
      contract type: "CandidateCommitRangeDeclared", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :head_commit_oid, Types::GitOid
    end
  end
end
