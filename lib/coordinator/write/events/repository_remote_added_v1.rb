# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryRemoteAddedV1 < Base
      contract type: "RepositoryRemoteAdded", version: 1

      attribute :repository_id, Types::UuidV7
      attribute :remote, Types::String.constrained(min_size: 1, max_size: 2_048)
    end
  end
end
