# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationViewV1 < Value
    attribute :relation_id, Types::DevelopmentArtifactRelationId
    attribute :source_artifact_id, Types::DevelopmentArtifactId
    attribute :relation, Types::DevelopmentArtifactRelationKind
    attribute :display_relation, Types::String
    attribute :inverse_relation, Types::String
    attribute :transitive, Types::Strict::Bool
    attribute :supersedable, Types::Strict::Bool
    attribute :target, Coordinator::Write::DevelopmentArtifacts::RelationTargetV1
    attribute :attributes, Coordinator::Write::DevelopmentArtifacts::RelationAttributesV1
    attribute :direction, Types::String.enum("incoming", "outgoing")
    attribute :peer_kind, Types::DevelopmentArtifactTargetKind
    attribute :peer_id, Types::DevelopmentArtifactTargetId
    attribute :peer_artifact, DevelopmentArtifactSummaryV1.optional
    attribute :status, Types::String.enum("active", "superseded")
    attribute :observed_sequence, Types::Integer.constrained(gteq: 1)
    attribute :declared, DevelopmentArtifactEventEvidenceV1
    attribute :replacement_relation_id, Types::DevelopmentArtifactRelationId.optional
    attribute :supersession_reason,
              Types::DevelopmentArtifactRelationSupersessionReason.optional
    attribute :superseded, DevelopmentArtifactEventEvidenceV1.optional
    attribute :follow_action, Coordinator::Write::NextAction.optional

    def relation_attributes
      self[:attributes]
    end
  end
end
