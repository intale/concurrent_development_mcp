# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class VerificationFindingV1 < Value
      attribute :code, Types::ReleaseSetFailureCode
      attribute :severity, Types::ReleaseSetFindingSeverity
      attribute :summary, Types::ReleaseSetEvidenceSummary
      attribute :repository_id, Types::RepositoryId.optional
    end
  end
end
