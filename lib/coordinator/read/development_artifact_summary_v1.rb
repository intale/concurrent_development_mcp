# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactSummaryV1 < Value
    attribute :artifact_id, ProjectedDevelopmentArtifactId
    attribute :stream_revision, Types::Integer.constrained(gteq: 0)
    attribute :observation_id, ProjectedDevelopmentArtifactObservationId
    attribute :scope, Types::DevelopmentArtifactScope
    attribute :title, Types::DevelopmentArtifactTitle
    attribute :kind, Types::DevelopmentArtifactKind
    attribute :labels, Types::DevelopmentArtifactLabels
    attribute :media_type, Types::DevelopmentArtifactMediaType
    attribute :encoding, Types::DevelopmentArtifactEncoding
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::DevelopmentArtifactByteSize
    attribute :source, DevelopmentArtifactProvenanceV1
    attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
    attribute :classification_reason, Types::String.optional
    attribute :relationship_count, Types::Integer.constrained(gteq: 0)
    attribute :relationship_capacity, DevelopmentArtifactRelationshipCapacityV1
    attribute :captured, DevelopmentArtifactEventEvidenceV1
    attribute :observed, DevelopmentArtifactEventEvidenceV1
    attribute :classified, DevelopmentArtifactEventEvidenceV1
  end
end
