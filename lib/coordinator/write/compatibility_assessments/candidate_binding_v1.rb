# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class CandidateBindingV1 < Value
      attribute :candidate_id, Types::Identifier
      attribute :head_commit_oid, Types::GitOid
    end
  end
end
