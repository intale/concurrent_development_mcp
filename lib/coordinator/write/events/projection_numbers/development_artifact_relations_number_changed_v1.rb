# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class DevelopmentArtifactRelationsNumberChangedV1 < Coordinator::Write::Events::Base
    contract type: "DevelopmentArtifactRelationsNumberChanged", version: 1

    RelationNumber = Coordinator::Write::Types::Integer.constrained(
      gteq: 0, lteq: Coordinator::Write::Types::DEVELOPMENT_ARTIFACT_RELATION_LIFETIME_MAXIMUM_COUNT
    )
    attribute :artifact_id, Coordinator::Write::Types::DevelopmentArtifactId
    attribute :active_relations_number, RelationNumber
    attribute :lifetime_relations_number, RelationNumber
  end
end
