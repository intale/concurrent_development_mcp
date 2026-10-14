# frozen_string_literal: true

module Coordinator::Write::ProjectionStatistics
  class CheckpointStateV1 < Coordinator::Write::Value
    attribute :statistics_id, Coordinator::Write::Types::UuidV7
    attribute :change_set_id, Coordinator::Write::Types::Identifier.optional
    attribute :repository_id, Coordinator::Write::Types::RepositoryId.optional
    attribute :checkpoints_number, Coordinator::Write::Types::Integer.optional
    attribute :latest_revision, Coordinator::Write::Types::Integer.constrained(gteq: -1)

    def initialized?
      !change_set_id.nil? && !repository_id.nil? && !checkpoints_number.nil?
    end
  end
end
