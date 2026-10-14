# frozen_string_literal: true

module Coordinator::Read
  module CommandResults
    class Source
      attr_reader :terminal_event, :registration, :input, :persisted_events

      def initialize(terminal_event:, registration:, input:, persisted_events:)
        @terminal_event, @registration, @persisted_events = terminal_event, registration, persisted_events
        @input = self.class.document(input)
      end

      def self.document(value)
        case value
        when Hash then value.to_h { |key, nested| [ key.to_sym, document(nested) ] }
        when Array then value.map { document(_1) }
        else value
        end
      end

      def command_id = terminal_event.stream.stream_id
      def request_id = registration.data.fetch("request_id")
      def tool_name = registration.data.fetch("tool_name")
      def canonical_input_digest = registration.metadata.fetch("canonical_input_digest")
      def completed_at = timestamp(terminal_event)
      def event(type) = persisted_events.find { _1.type == type }
      def events(*types) = persisted_events.select { types.include?(_1.type) }
      def data(event) = self.class.document(event.data)
      def fact(type) = data(event(type))
      def timestamp(event) = event.created_at.utc.iso8601(6)
      def reference(event) = Projections::Source.reference(event)

      def values(*keys)
        input.slice(*keys)
      end

      def action(tool, **arguments)
        { tool:, arguments: }
      end

      def presentation(summary, data, next_actions: [], warnings: [])
        { summary:, data:, next_actions:, warnings: }
      end
    end
  end
end
