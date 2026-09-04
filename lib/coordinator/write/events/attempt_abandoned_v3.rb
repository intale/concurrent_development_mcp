# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptAbandonedV3 < Base
      contract type: "AttemptAbandoned", version: 3

      attribute :attempt_id, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
    end
  end
end
