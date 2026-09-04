# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetActivatedV2 < Base
      contract type: "ChangeSetActivated", version: 2

      attribute :change_set_id, Types::Identifier
    end
  end
end
