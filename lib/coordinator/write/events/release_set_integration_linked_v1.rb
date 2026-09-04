# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetIntegrationLinkedV1 < Base
      contract type: "ReleaseSetIntegrationLinked", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :integration_event, EventReference
    end
  end
end
