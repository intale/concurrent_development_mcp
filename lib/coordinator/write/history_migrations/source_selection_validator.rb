# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceSelectionValidator
      include Dry::Monads[:result]

      MAXIMUM_FACTS = 1000
      TOOLS = %w[development_artifact_capture development_artifact_update].freeze
      REFERENCE_KEYS = %w[event_id type stream_context stream_name stream_id stream_revision].freeze

      def initialize(source_reader:, schema_registry: SourceEventSchemaRegistry.new)
        @source_reader = source_reader
        @schema_registry = schema_registry
      end

      def call(after_position:, upper_position:, command_ids:)
        criteria = SourcePageCriteriaV1.new(
          from_position: after_position + 1, to_position: upper_position,
          page_size: MAXIMUM_FACTS, source_command_ids: command_ids
        )
        events = @source_reader.page(criteria)
        return invalid("Selected source history is empty") if events.empty?
        sentinel = @source_reader.page(criteria.new(from_position: events.last.global_position + 1, page_size: 1))
        return invalid("Selected source history exceeds #{MAXIMUM_FACTS} facts") unless sentinel.empty?

        registered = events.select { _1.type == "CommandRegistered" }
        unless registered.map { _1.data.fetch("command_id") }.sort == command_ids.sort &&
            registered.all? { TOOLS.include?(_1.data.fetch("tool_name")) }
          return invalid("Selection requires complete artifact capture/update commands")
        end
        terminals = events.select { %w[CommandSucceeded CommandRejected].include?(_1.type) }
        unless terminals.map { _1.data.fetch("command_id") }.sort == command_ids.sort
          return invalid("Selection requires terminal command outcomes")
        end
        streams = events.group_by { [ _1.stream.context, _1.stream.stream_name, _1.stream.stream_id ] }
        incomplete = streams.values.find do |history|
          !(
            history.map(&:stream_revision) == (0...history.length).to_a &&
              history.last.global_position == @source_reader.stream_tail_position(history.last, to_position: upper_position) &&
              (history.first.stream.stream_name != "CoordinationTask" || history.last.type == "CoordinationTaskCompleted")
          )
        end
        if incomplete
          event = incomplete.last
          return invalid("Selection must contain complete new source streams: #{event.stream.stream_name}/#{event.stream.stream_id} revisions #{incomplete.map(&:stream_revision).join(',')}")
        end
        identities = events.index_by(&:id)
        events.each do |event|
          @schema_registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data)
          if event.causation_id
            parent = identities[event.causation_id]
            unless parent && parent.correlation_id == event.correlation_id
              return invalid("Selection omits an immediate causal parent or changes its correlation")
            end
          end
          return invalid("Selection omits a concrete source-event reference") unless references_present?(event.data, identities)
        end
        Success()
      rescue KeyError, Dry::Struct::Error, EventSchemaRegistry::SchemaMismatch, EventHistoryLimitExceeded => error
        invalid("Selected source contracts are invalid: #{error.message}")
      end

      private

      def references_present?(value, identities)
        case value
        when Hash
          if REFERENCE_KEYS.all? { value.key?(_1) }
            referenced = identities[value.fetch("event_id")]
            return false unless referenced

            reference = EventReference.new(value.slice(*REFERENCE_KEYS).transform_keys(&:to_sym))
            reference == EventReference.new(
              event_id: referenced.id, type: referenced.type,
              stream_context: referenced.stream.context, stream_name: referenced.stream.stream_name,
              stream_id: referenced.stream.stream_id, stream_revision: referenced.stream_revision
            )
          else
            value.each_value.all? { references_present?(_1, identities) }
          end
        when Array
          value.all? { references_present?(_1, identities) }
        else
          true
        end
      end

      def invalid(message)
        Failure(OutcomeError.new(code: :invalid_input, message:, details: {}))
      end
    end
  end
end
