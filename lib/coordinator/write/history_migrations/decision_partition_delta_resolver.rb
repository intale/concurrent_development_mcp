# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionPartitionDeltaResolver
      include Dry::Monads[:result]

      def initialize(event_store:, schema_registry: LegacyEventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(source_event:, source_upper_position:)
        history = load_history(source_event:, source_upper_position:)
        return history if history.failure?

        delta = history.value!.find { _1.source_event.id == source_event.id }
        return Success(delta) if delta

        Failure(inconsistent(source_event, "current partition event is absent from its bounded history"))
      end

      def membership(source_event:, source_upper_position:, source_head:)
        history = load_history(source_event:, source_upper_position:)
        return history if history.failure?

        source_decision_id = source_head.decision_id
        current = history.value!.last.source_payload
        active = current.active_decisions.any? do |head|
          head.decision_id == source_decision_id && head.event == source_head.event
        end
        relevant = history.value!.reverse.find do |delta|
          next false unless delta.source_payload.decision.decision_id == source_decision_id

          active ? delta.add : delta.remove
        end
        return Failure(inconsistent(source_event, "partition history has no exact membership delta")) unless relevant

        Success([ relevant, active ? "add-decision-to-partition" : "remove-decision-from-partition" ])
      end

      private

      def load_history(source_event:, source_upper_position:)
        events = @event_store.read(
          stream_for(source_event),
          EventReadCriteria.new(
            event_types: [ "DecisionPartitionAdvanced" ],
            maximum_count: source_event.stream_revision + 1,
            direction: :asc,
            to_revision: source_event.stream_revision
          )
        )
        unless events.length == source_event.stream_revision + 1 &&
            events.last&.id == source_event.id &&
            events.all? { _1.global_position <= source_upper_position }
          return Failure(inconsistent(source_event, "partition history is incomplete in the frozen source range"))
        end

        active = {}
        target_revision = 0
        deltas = events.map do |event|
          payload = load(event)
          decision_id = payload.decision.decision_id
          before = active.key?(decision_id)
          after_head = payload.active_decisions.find { _1.decision_id == decision_id }
          after = !after_head.nil?
          unless before || after
            return Failure(inconsistent(source_event, "partition advancement contains no decision delta"))
          end

          delta = DecisionPartitionDeltaV1.new(
            source_event: event,
            source_payload: payload,
            remove: before,
            add: after,
            first_target_revision: target_revision
          )
          target_revision += (before ? 1 : 0) + (after ? 1 : 0)
          active = payload.active_decisions.to_h { [ _1.decision_id, _1 ] }
          delta
        end
        Success(deltas.freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load(event)
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        return payload if payload.is_a?(Events::DecisionPartitionAdvancedV1)

        raise TypeError, "unexpected partition contract"
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Decision partition source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
