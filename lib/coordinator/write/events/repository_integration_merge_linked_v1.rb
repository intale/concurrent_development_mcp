# frozen_string_literal: true

module Coordinator::Write
  module Events
    class RepositoryIntegrationMergeLinkedV1 < Base
      contract type: "RepositoryIntegrationMergeLinked", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :repository_id, Types::RepositoryId
      attribute :merge_observation, EventReference
    end
  end
end
