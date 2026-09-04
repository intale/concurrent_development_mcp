# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptAuthorizedV2 < Base
      contract type: "AttemptAuthorized", version: 2

      attribute :attempt_id, Types::Identifier
    end
  end
end
