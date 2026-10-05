# frozen_string_literal: true

module HistoryMigrationCandidateFixture
  def self.persist_reservation(event_store:, candidate:)
    payload = Coordinator::Write::Events::WriteSetReservedV2.new(
      lease_set_id: candidate.lease_set_id,
      change_set_id: candidate.change_set_id,
      work_item_id: candidate.work_item_id,
      attempt_id: candidate.attempt_id,
      repository_id: candidate.repository_id,
      policy_version: candidate.lease_policy_version,
      resources: candidate.lease_references,
      reserved_at: "2001-07-01T00:00:00.000000Z",
      expires_at: "2001-07-02T00:00:00.000000Z"
    )
    event_store.append(
      Coordinator::Write::StreamReference.new(context: "DevelopmentExecution", stream_name: "Attempt", stream_id: candidate.attempt_id),
      [ PgEventstore::Event.new(
        id: SecureRandom.uuid_v7, type: payload.class.event_type, data: payload.to_h,
        metadata: { "schema_version" => payload.class.schema_version },
        markers: [ "lease-set:#{candidate.lease_set_id}" ]
      ) ]
    ).sole
  end
end
