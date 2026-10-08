# frozen_string_literal: true

# Concrete authoritative history for bounded command-layer tests; no subscriptions
# or projections participate in fixture creation.
module WorkIntentionHistoryFixture
  module_function

  def exhaust_boundary(event_store:, declaration:)
    factory = Coordinator::Write::EventFactory.new
    resource_id = declaration.data.fetch("resource_id")
    intention_id = declaration.data.fetch("intention_id")
    deadline = Time.iso8601(declaration.data.fetch("expires_at"))
    metadata = Coordinator::Write::EventMetadata.new(
      command_id: "seed-intention-renewal-history",
      actor_kind: "agent",
      actor_id: declaration.data.fetch("agent_id"),
      recorded_by: "coordinator",
      policy_version: Coordinator::Write::WorkIntentionPolicyV1::VERSION
    )
    events = Coordinator::Write::EventQueries::WORK_INTENTION_BOUNDARY_MAXIMUM_COUNT.times.map do |index|
      payload = Coordinator::Write::Events::ResourceWorkIntentionRenewedV1.new(
        intention_id:,
        resource_id:,
        fencing_token: declaration.data.fetch("fencing_token"),
        expires_at: (deadline + Rational(index + 1, 1_000_000)).utc.iso8601(6)
      )
      factory.build!(
        event: payload,
        event_id: SecureRandom.uuid_v7,
        metadata:,
        markers: declaration.markers,
        caused_by: declaration
      )
    end
    stream = Coordinator::Write::StreamFactory.new.resource_work_intention(intention_id)
    # Keep real SDK writes small: its instrumented variadic SQL methods cannot
    # type-check thousands of bound values in one call without exhausting stack.
    events.each_slice(64).flat_map { event_store.append(stream, _1) }
  end
end
