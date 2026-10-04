# frozen_string_literal: true

class HistoryMigrationProjectionContract
  def self.call(event, contract)
    envelope = {
      event_type: event.type, schema_version: event.metadata["schema_version"],
      stream_context: event.stream.context, stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id, stream_revision: event.stream_revision,
      global_position: event.global_position, policy_version: event.metadata["policy_version"]
    }
    attributes = event.metadata.symbolize_keys.merge(envelope)
    contract.call(attributes.slice(*contract.schema.key_map.keys.map { _1.name.to_sym }))
  end
end
