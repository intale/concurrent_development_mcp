# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryCompensationRecordedV1 < Base
      contract type: "RepositoryCompensationRecorded", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :integration_event, EventReference
      attribute :action, Types::ReleaseSetCompensationAction
      attribute :external_reference, Types::ReleaseSetExternalReference
    end
  end
end
