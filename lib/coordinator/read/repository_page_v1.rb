# frozen_string_literal: true

module Coordinator::Read
  class RepositoryPageV1 < Value
    attribute :items, Types::Array.of(RepositorySummaryV1).constrained(max_size: 100)
    attribute :next_repository_id, Types::UuidV7.optional
    attribute :has_more, Types::Bool
  end
end
