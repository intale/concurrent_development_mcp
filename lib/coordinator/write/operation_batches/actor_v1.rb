# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class ActorV1 < Value
      attribute :kind, Types::ActorKind
      attribute :id, Types::Identifier
    end
  end
end
