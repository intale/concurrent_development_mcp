# frozen_string_literal: true

module Coordinator
  module Events
    class ChangeSetActivatedV1 < Base
      contract type: "ChangeSetActivated", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :work_item_count, Types::Integer.constrained(gteq: 1, lteq: 100)
      attribute :dependency_count, Types::Integer.constrained(gteq: 0, lteq: 500)
      attribute :activated_at, Types::Timestamp
    end
  end
end
