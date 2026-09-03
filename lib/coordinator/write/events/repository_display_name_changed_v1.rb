# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryDisplayNameChangedV1 < Base
      contract type: "RepositoryDisplayNameChanged", version: 1

      attribute :repository_id, Types::UuidV7
      attribute :display_name, Types::String.constrained(min_size: 1, max_size: 255).optional
    end
  end
end
