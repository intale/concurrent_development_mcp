# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryRegisteredV2 < Base
      contract type: "RepositoryRegistered", version: 2

      attribute :repository_id, Types::UuidV7
      attribute :scope, Types::String.constrained(min_size: 1, max_size: 500)
      attribute :repository_key, Types::Identifier.optional
    end
  end
end
