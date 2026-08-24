# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class FindingV1 < Value
      attribute :code, Types::VerificationEvidenceFindingCode
      attribute :severity, Types::VerificationEvidenceFindingSeverity
      attribute :summary, Types::VerificationEvidenceFindingSummary
      attribute? :path, Types::ResourcePath.optional
    end
  end
end
