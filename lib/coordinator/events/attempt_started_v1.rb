# frozen_string_literal: true

module Coordinator
  module Events
    class AttemptStartedV1 < Base
      contract type: "AttemptStarted", version: 1

      attribute :attempt_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :started_at, Types::Timestamp
    end
  end
end
