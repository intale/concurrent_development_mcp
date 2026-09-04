# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetCompletedV2 < Base
      contract type: "ChangeSetCompleted", version: 2

      attribute :change_set_id, Types::Identifier
    end
  end
end
