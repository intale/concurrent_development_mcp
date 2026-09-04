# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ChangeSetReleaseSetLinkedV1 < Base
      contract type: "ChangeSetReleaseSetLinked", version: 1

      attribute :change_set_id, Types::Identifier
      attribute :release_set_id, Types::Identifier
    end
  end
end
