# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetPreparedV2 < Base
      contract type: "ReleaseSetPrepared", version: 2

      attribute :release_set_id, Types::Identifier
    end
  end
end
