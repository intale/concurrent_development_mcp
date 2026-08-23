# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class BuildInputV1 < Value
      attribute :kind, Types::CandidateBuildInputKind
      attribute :path, Types::ResourcePath
      attribute :blob_oid, Types::GitOid
    end
  end
end
