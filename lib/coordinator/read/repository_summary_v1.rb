# frozen_string_literal: true

module Coordinator::Read
  class RepositorySummaryV1 < Value
    attribute :repository_id, Types::UuidV7
    attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
    attribute :display_name, Types::String.constrained(min_size: 1, max_size: 255).optional
    attribute :paths,
              Types::Array.of(Types::String.constrained(min_size: 1, max_size: 1_024)).constrained(max_size: 20)
    attribute :remotes,
              Types::Array.of(Types::String.constrained(min_size: 1, max_size: 2_048)).constrained(max_size: 20)
    attribute :registered, RepositorySourceEvidenceV1
  end
end
