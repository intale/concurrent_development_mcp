# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module WorkIntentions
      class State < Value
        attribute :intention_id, Types::UuidV7.optional
        attribute :set_id, Types::UuidV7.optional
        attribute :resource_id, Types::ResourceId.optional
        attribute :repository_id, Types::RepositoryId.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :work_item_id, Types::Identifier.optional
        attribute :attempt_id, Types::Identifier.optional
        attribute :agent_id, Types::Identifier.optional
        attribute :mode, Types::WorkIntentionMode.optional
        attribute :purpose, Types::WorkIntentionPurpose.optional
        attribute :context, Types::WorkIntentionContext.optional
        attribute :object_format, Types::GitObjectFormat.optional
        attribute :base_commit_oid, Types::GitOid.optional
        attribute :base_blob_oid, Types::GitOid.optional
        attribute :fencing_token, Types::Integer.constrained(gteq: 0)
        attribute :expires_at, Types::Timestamp.optional
        attribute :withdrawn, Types::Bool
        attribute :withdrawal_reason, Types::String.optional
        attribute :expired, Types::Bool

        def self.initial
          new(
            intention_id: nil,
            set_id: nil,
            resource_id: nil,
            repository_id: nil,
            change_set_id: nil,
            work_item_id: nil,
            attempt_id: nil,
            agent_id: nil,
            mode: nil,
            purpose: nil,
            context: nil,
            object_format: nil,
            base_commit_oid: nil,
            base_blob_oid: nil,
            fencing_token: 0,
            expires_at: nil,
            withdrawn: false,
            withdrawal_reason: nil,
            expired: false
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def absent?
          intention_id.nil?
        end

        def active_at?(timestamp)
          !absent? && !withdrawn && !expired && expires_at > timestamp
        end

        def apply(event)
          case event
          when Events::ResourceWorkIntentionDeclaredV1
            self.class.new(
              intention_id: event.intention_id,
              set_id: event.set_id,
              resource_id: event.resource_id,
              repository_id: event.repository_id,
              change_set_id: event.change_set_id,
              work_item_id: event.work_item_id,
              attempt_id: event.attempt_id,
              agent_id: event.agent_id,
              mode: event.mode,
              purpose: event.purpose,
              context: event.context,
              object_format: event.object_format,
              base_commit_oid: event.base_commit_oid,
              base_blob_oid: event.base_blob_oid,
              fencing_token: event.fencing_token,
              expires_at: event.expires_at,
              withdrawn: false,
              withdrawal_reason: nil,
              expired: false
            )
          when Events::ResourceWorkIntentionRenewedV1
            rebuild(expires_at: event.expires_at)
          when Events::ResourceWorkIntentionWithdrawnV1
            rebuild(withdrawn: true, withdrawal_reason: event.reason)
          when Events::ResourceWorkIntentionExpiredV1
            rebuild(expired: true)
          else
            self
          end
        end

        private

        def rebuild(**changes)
          self.class.new(attributes.merge(changes))
        end
      end
    end
  end
end
