# frozen_string_literal: true

module ProjectionEventFactory
  module_function

  def build(
    payload:,
    stream:,
    stream_revision:,
    global_position:,
    policy_version:,
    command_id: "cmd-projector-spec",
    actor_kind: "agent",
    actor_id: "projector-spec-agent",
    recorded_by: "coordinator",
    markers: [],
    metadata: {},
    event_id: SecureRandom.uuid_v7,
    created_at: Time.utc(2026, 8, 30, 12),
    correlation_id: SecureRandom.uuid_v7,
    causation_id: nil,
    caused_by: nil
  )
    event = Coordinator::Write::EventFactory.new.build!(
      event: payload,
      event_id:,
      metadata: {
        command_id:,
        actor_kind:,
        actor_id:,
        recorded_by:,
        policy_version:
      }.merge(metadata),
      markers:,
      caused_by:,
      correlation_id:
    )
    event.stream = stream
    event.stream_revision = stream_revision
    event.global_position = global_position
    event.created_at = created_at
    event.causation_id = causation_id || caused_by&.id
    event
  end
end
