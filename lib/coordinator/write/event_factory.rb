# frozen_string_literal: true

module Coordinator::Write
  class EventFactory
    def initialize(registry: EventSchemaRegistry.new)
      @registry = registry
    end

    def build!(event:, event_id:, metadata:, markers:, caused_by: nil)
      @registry.verify!(event)
      Types::UuidV7[event_id]

      PgEventstore::Event.new(
        id: event_id,
        type: event.class.event_type,
        data: deep_stringify(event.to_h),
        metadata: deep_stringify(metadata.to_h.compact).merge(
          "schema_version" => event.class.schema_version
        ),
        markers: normalize_markers(markers),
        caused_by:
      )
    end

    private

    def normalize_markers(markers)
      markers.uniq.sort
    end

    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), output|
          string_key = key.to_s
          raise ArgumentError, "duplicate JSON key: #{string_key.inspect}" if output.key?(string_key)

          output[string_key] = deep_stringify(nested)
        end
      when Array
        value.map { deep_stringify(_1) }
      else
        value
      end
    end
  end
end
