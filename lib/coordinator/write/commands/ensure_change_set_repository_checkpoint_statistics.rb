# frozen_string_literal: true

module Coordinator::Write::Commands
  class EnsureChangeSetRepositoryCheckpointStatistics < Coordinator::Write::Value
    attribute :command_id, Coordinator::Write::Types::UuidV7
    attribute :actor, Actor
    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :change_set_id, Coordinator::Write::Types::Identifier
    attribute :repository_id, Coordinator::Write::Types::RepositoryId
  end
end
