# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class CandidateEvidenceV2 < Value
      attribute :registration, Events::CandidateImpactSurfaceAssignedV1
      attribute :registration_event, EventReference
      attribute :registration_global_position, Types::GlobalPosition
      attribute :candidate, Types.Instance(Candidates::StateV2)
      attribute :surface, Events::CandidateImpactSurfaceDerivedV2
      attribute :surface_event, EventReference
      attribute :surface_digest, Types::Sha256Digest
      attribute :subject, CandidateSubjectV1
    end
  end
end
