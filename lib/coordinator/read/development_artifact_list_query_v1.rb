# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactListQueryV1 < Value
    attribute :scope, Types::DevelopmentArtifactScope.optional
    attribute :kind, Types::DevelopmentArtifactKind.optional
    attribute :labels, Types::DevelopmentArtifactLabels
    attribute :source_kind, Types::DevelopmentArtifactSourceKind.optional
    attribute :relation_target_kind, Types::DevelopmentArtifactTargetKind.optional
    attribute :relation_target_id, Types::DevelopmentArtifactTargetId.optional
    attribute :after_global_position, Types::GlobalPosition.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS)
  end
end
