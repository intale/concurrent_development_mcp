# frozen_string_literal: true

module Coordinator::Read
  module CoordContexts
    class WorkIntentionStateV1 < Value
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

      def self.reduce(events)
        declaration = events.find do
          _1.is_a?(Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1)
        end
        raise InvalidProjectionSource, "Work intention is missing its declaration fact" unless declaration

        expiration = events.reverse.find { _1.respond_to?(:expires_at) }
        new(
          intention_id: declaration.intention_id,
          set_id: declaration.set_id,
          resource_id: declaration.resource_id,
          repository_id: declaration.repository_id,
          change_set_id: declaration.change_set_id,
          work_item_id: declaration.work_item_id,
          attempt_id: declaration.attempt_id,
          agent_id: declaration.agent_id,
          mode: declaration.mode,
          purpose: declaration.purpose,
          context: declaration.context,
          object_format: declaration.object_format,
          base_commit_oid: declaration.base_commit_oid,
          base_blob_oid: declaration.base_blob_oid,
          fencing_token: declaration.fencing_token,
          expires_at: expiration.expires_at
        )
      end
    end
  end
end
