# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateBuildContextCapturedV2 < Base
      Input = Candidates::BuildInputV1
      Environment = Candidates::EnvironmentEntryV1

      contract type: "CandidateBuildContextCaptured", version: 2

      attribute :candidate_id, Types::Identifier
      attribute :evidence_revision, Types::CandidateEvidenceRevision
      attribute :inputs, Types::Array.of(Input).constrained(max_size: 64)
      attribute :environment, Types::Array.of(Environment).constrained(max_size: 32)
    end
  end
end
