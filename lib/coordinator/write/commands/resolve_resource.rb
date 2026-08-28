# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ResolveResource < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :identity, ResourceIdentityV1

      delegate :repository_id, :kind, :normalized_path, to: :identity
    end
  end
end
