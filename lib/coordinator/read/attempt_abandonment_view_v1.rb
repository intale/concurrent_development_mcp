# frozen_string_literal: true

module Coordinator::Read
  class AttemptAbandonmentViewV1 < Value
    attribute :attempt_id, Types::Identifier
    attribute :change_set_id, Types::Identifier
    attribute :work_item_id, Types::Identifier
    attribute :agent_id, Types::Identifier
    attribute :reason, Types::String
    attribute :abandoned_at, Types::Timestamp
  end
end
