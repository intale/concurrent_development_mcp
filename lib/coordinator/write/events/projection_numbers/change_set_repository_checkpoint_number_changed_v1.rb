# frozen_string_literal: true

module Coordinator::Write::Events::ProjectionNumbers
  class ChangeSetRepositoryCheckpointNumberChangedV1 < Coordinator::Write::Events::Base
    contract type: "ChangeSetRepositoryCheckpointNumberChanged", version: 1

    attribute :change_set_id, Coordinator::Write::Types::Identifier
    attribute :repository_id, Coordinator::Write::Types::RepositoryId
    attribute :checkpoints_number, Coordinator::Write::Types::Integer.constrained(gteq: 0)
  end
end
