# frozen_string_literal: true

module Coordinator::Read
  class RepositoryListQueryV1 < Value
    attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
    attribute :after_repository_id, Types::UuidV7.optional
    attribute :limit, Types::Integer.constrained(gteq: 1, lteq: 100)
  end
end
