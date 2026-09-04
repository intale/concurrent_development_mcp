# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptCompletedV2 < Base
      contract type: "AttemptCompleted", version: 2

      attribute :attempt_id, Types::Identifier
    end
  end
end
