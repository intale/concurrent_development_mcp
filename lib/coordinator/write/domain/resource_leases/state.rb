# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module ResourceLeases
      class State < Value
        attribute :lease_id, Types::UuidV7.optional
        attribute :lease_set_id, Types::UuidV7.optional
        attribute :resource_key, Types::String.optional
        attribute :resource_key_hash, Types::Sha256Digest.optional
        attribute :attempt_id, Types::Identifier.optional
        attribute :agent_id, Types::Identifier.optional
        attribute :fencing_token, Types::Integer.constrained(gteq: 0)
        attribute :acquired_at, Types::Timestamp.optional
        attribute :expires_at, Types::Timestamp.optional

        def self.initial
          new(
            lease_id: nil,
            lease_set_id: nil,
            resource_key: nil,
            resource_key_hash: nil,
            attempt_id: nil,
            agent_id: nil,
            fencing_token: 0,
            acquired_at: nil,
            expires_at: nil
          )
        end

        def self.reduce(events)
          events.reduce(initial) { |state, event| state.apply(event) }
        end

        def active_at?(timestamp)
          !lease_id.nil? && expires_at > timestamp
        end

        def next_fencing_token
          fencing_token + 1
        end

        def apply(event)
          return self unless event.is_a?(Events::ResourceLeaseAcquiredV1)

          self.class.new(
            lease_id: event.lease_id,
            lease_set_id: event.lease_set_id,
            resource_key: event.resource_key,
            resource_key_hash: event.resource_key_hash,
            attempt_id: event.attempt_id,
            agent_id: event.agent_id,
            fencing_token: event.fencing_token,
            acquired_at: event.acquired_at,
            expires_at: event.expires_at
          )
        end
      end
    end
  end
end
