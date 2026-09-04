# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ResourceWorkIntentionDeclaredV1 < Base
      contract type: "ResourceWorkIntentionDeclared", version: 1

      attribute :intention_id, Types::UuidV7
      attribute :set_id, Types::UuidV7
      attribute :resource_id, Types::ResourceId
      attribute :repository_id, Types::RepositoryId
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
      attribute :mode, Types::WorkIntentionMode
      attribute :purpose, Types::WorkIntentionPurpose
      attribute :context, Types::WorkIntentionContext.optional
      attribute :object_format, Types::GitObjectFormat
      attribute :base_commit_oid, Types::GitOid
      attribute :base_blob_oid, Types::GitOid.optional
      attribute :fencing_token, Types::FencingToken
      attribute :expires_at, Types::Timestamp
    end
  end
end
