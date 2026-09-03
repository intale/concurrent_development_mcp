# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryPathRemovedV1 < Base
      contract type: "RepositoryPathRemoved", version: 1

      attribute :repository_id, Types::UuidV7
      attribute :path, Types::String.constrained(min_size: 1, max_size: 1_024)
    end
  end
end
