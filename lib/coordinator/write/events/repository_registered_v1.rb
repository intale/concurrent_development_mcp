# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryRegisteredV1 < Base
      contract type: "RepositoryRegistered", version: 1

      attribute :repository_id, Types::UuidV7
      attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
      attribute? :repository_key, Types::Identifier.optional
      attribute :display_name, Types::String.constrained(min_size: 1, max_size: 255).optional
      attribute :paths,
                Types::Array.of(Types::String.constrained(min_size: 1, max_size: 1_024)).constrained(max_size: 20)
      attribute :remotes,
                Types::Array.of(Types::String.constrained(min_size: 1, max_size: 2_048)).constrained(max_size: 20)
      attribute :registered_at, Types::Timestamp
    end
  end
end
