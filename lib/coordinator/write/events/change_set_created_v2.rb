# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetCreatedV2 < Base
      contract type: "ChangeSetCreated", version: 2

      attribute :change_set_id, Types::Identifier
    end
  end
end
