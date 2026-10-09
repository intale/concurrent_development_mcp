# frozen_string_literal: true

module Coordinator::Processes
  class WorkIntentionExpiryCommandBuilder
    POLICY_ID = "lease-expiry-policy-v1"
    def call(source, command_id:)
      payload = source.payload
      state = source.state
      Coordinator::Write::Commands::ExpireWorkIntention.new(
        command_id:,
        actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: POLICY_ID),
        resource_id: state.resource_id,
        intention_id: payload.intention_id,
        intention_set_id: state.set_id,
        fencing_token: payload.fencing_token,
        expected_expires_at: payload.expires_at
      )
    end
  end
end
