# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetSuccessfulIntegrationLinkedV1 < Base
      contract type: "ReleaseSetSuccessfulIntegrationLinked", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :integration_event, EventReference
    end
  end
end
