# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetCreatedV1 < Base
      contract type: "ReleaseSetCreated", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
    end
  end
end
