# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ActivateChangeSet < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
    end
  end
end
