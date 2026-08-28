# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RegisterRepository < Value
      Scope = Types::String.constrained(min_size: 1, max_size: 500)
      DisplayName = Types::String.constrained(min_size: 1, max_size: 255)
      Path = Types::String.constrained(min_size: 1, max_size: 1_024)
      Remote = Types::String.constrained(min_size: 1, max_size: 2_048)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :repository_id, Types::UuidV7
      attribute :scope, Scope
      attribute :repository_key, Types::Identifier
      attribute :display_name, DisplayName.optional
      attribute :paths, Types::Array.of(Path).constrained(max_size: 20)
      attribute :remotes, Types::Array.of(Remote).constrained(max_size: 20)
    end
  end
end
