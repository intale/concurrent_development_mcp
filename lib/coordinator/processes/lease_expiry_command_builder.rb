# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpiryCommandBuilder
    POLICY_ID = "lease-expiry-policy-v1"
    def call(source, command_id:)
      payload = source.payload
      Coordinator::Write::Commands::ExpireResourceLease.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: POLICY_ID),
        resource_id: payload.resource_id,
        lease_id: payload.lease_id,
        lease_set_id: payload.lease_set_id,
        fencing_token: payload.fencing_token,
        expected_expires_at: payload.expires_at
      )
    end
  end
end
