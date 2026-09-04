# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateTargetBranchSelectedV1 < Base
      contract type: "CandidateTargetBranchSelected", version: 1

      attribute :candidate_id, Types::Identifier
      attribute :target_branch, Types::CandidateTargetBranch
    end
  end
end
