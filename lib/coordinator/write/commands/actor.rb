# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class Actor < Value
      attribute :kind, Types::ActorKind
      attribute :id, Types::Identifier
    end
  end
end
