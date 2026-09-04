# frozen_string_literal: true

module Coordinator::Read
  class CandidateImpactSurfaceSourceV2 < Value
    attribute :surface, Coordinator::Write::Events::CandidateImpactSurfaceDerivedV2
    attribute :event, Types.Instance(PgEventstore::Event)
  end
end
