# frozen_string_literal: true

module Coordinator
  module Read
    Types = Shared::Types
    Value = Shared::Value
    CanonicalJson = Shared::CanonicalJson

    # Target projections contain UUIDv7 identities. Until MIGRATION-01 rebuilds the
    # historical rows, read values must also be able to expose their persisted IDs.
    # This compatibility does not weaken write-side identity contracts.
    precutover_id = lambda do |prefix|
      Types::String.constrained(
        format: Regexp.new("\\A#{Regexp.escape(prefix)}:v1:[0-9a-f]{64}\\z")
      )
    end
    ProjectedSkillId = Types::SkillId
    ProjectedDevelopmentArtifactId =
      Types::DevelopmentArtifactId | precutover_id.call("artifact")
    ProjectedDevelopmentArtifactObservationId =
      Types::DevelopmentArtifactObservationId | precutover_id.call("artifact-observation")
    ProjectedDevelopmentArtifactRelationId =
      Types::DevelopmentArtifactRelationId | precutover_id.call("artifact-relation")
  end
end
