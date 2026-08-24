# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class FindingV1 < Value
      attribute :code, Types::VerificationEvidenceFindingCode
      attribute :severity, Types::VerificationEvidenceFindingSeverity
      attribute :summary, Types::VerificationEvidenceFindingSummary
      attribute :path, Types::ResourcePath.optional
    end
  end
end
