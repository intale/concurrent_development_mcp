# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactSummaryV1 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
    attribute :scope, Types::DevelopmentArtifactScope
    attribute :title, Types::DevelopmentArtifactTitle
    attribute :kind, Types::DevelopmentArtifactKind
    attribute :labels, Types::DevelopmentArtifactLabels
    attribute :media_type, Types::DevelopmentArtifactMediaType
    attribute :encoding, Types::DevelopmentArtifactEncoding
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::DevelopmentArtifactByteSize
    attribute :source, DevelopmentArtifactProvenanceV1
    attribute :relationship_count, Types::Integer.constrained(gteq: 0)
    attribute :captured, DevelopmentArtifactEventEvidenceV1
  end
end
