# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class ImpactSurfaceEvidenceV2 < Value
      attribute :candidate, Types.Instance(StateV2)

      def manifest
        candidate.manifest
      end

      def build_context
        candidate.build_context
      end
    end
  end
end
