# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class DevelopmentArtifactRelationStatisticsAssignedV1 < Coordinator::Write::Events::Base
    contract type: "DevelopmentArtifactRelationStatisticsAssigned", version: 1

    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :artifact_id, Coordinator::Write::Types::DevelopmentArtifactId
  end
end
