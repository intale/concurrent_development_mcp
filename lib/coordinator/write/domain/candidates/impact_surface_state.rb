# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Candidates
      class ImpactSurfaceState < Value
        attribute :evidence, Coordinator::Write::Candidates::ImpactSurfaceEvidenceV2.optional
        attribute :existing_surface, EventReference.optional
      end
    end
  end
end
