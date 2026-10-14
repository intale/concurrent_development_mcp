# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class ChangeSetRepositoryCheckpointStatisticsAssignedV1 < Coordinator::Write::Events::Base
    contract type: "ChangeSetRepositoryCheckpointStatisticsAssigned", version: 1

    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :change_set_id, Coordinator::Write::Types::Identifier
    attribute :repository_id, Coordinator::Write::Types::RepositoryId
  end
end
