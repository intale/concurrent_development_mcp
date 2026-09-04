# frozen_string_literal: true

module Coordinator::Write
  module Events
    class WorkIntentionSetCreatedV1 < Base
      contract type: "WorkIntentionSetCreated", version: 1

      attribute :set_id, Types::UuidV7
      attribute :attempt_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
    end
  end
end
