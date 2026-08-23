# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactAnalyzerV1 < Value
      attribute :kind, Types::ActorKind
      attribute :id, Types::Identifier
      attribute :analyzer_version, Types::CandidateAnalyzerVersion
    end
  end
end
