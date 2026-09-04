# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptStartedV2 < Base
      contract type: "AttemptStarted", version: 2

      attribute :attempt_id, Types::Identifier
    end
  end
end
