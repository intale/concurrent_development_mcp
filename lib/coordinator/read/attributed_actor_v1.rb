# frozen_string_literal: true

module Coordinator::Read
  class AttributedActorV1 < Value
    attribute :kind, Types::ActorKind
    attribute :id, Types::Identifier
    attribute :authenticated, Types::Bool
  end
end
