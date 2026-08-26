# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkItemRequeuedV1 < Base
      contract type: "WorkItemRequeued", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :requeued_at, Types::Timestamp
    end
  end
end
