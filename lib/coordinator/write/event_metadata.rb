# frozen_string_literal: true

module Coordinator::Write
  class EventMetadata < Value
    attribute :command_id, Types::Identifier
    attribute :actor_kind, Types::ActorKind
    attribute :actor_id, Types::Identifier
    attribute :actor_authenticated, Types::Bool.default(false)
    attribute :recorded_by, Types::String.enum("coordinator")
    attribute :policy_version, Types::String.optional
  end
end
