# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetCompletedV2 < Base
      contract type: "ReleaseSetCompleted", version: 2

      attribute :release_set_id, Types::Identifier
    end
  end
end
