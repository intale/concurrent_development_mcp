# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class CandidateImpactPairScanV2 < EventMetadata
      attribute :index_policy_version, Types::CandidateImpactIndexPolicyVersion
    end
  end
end
