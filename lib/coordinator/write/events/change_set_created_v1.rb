# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetCreatedV1 < Base
      contract type: "ChangeSetCreated", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :goal, Types::Goal
      attribute :created_at, Types::Timestamp
    end
  end
end
