# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class CoordContextV1
      PROJECTION = ProjectionDefinition.new(name: "coord_context", version: 3)

      def initialize(
        contract: Contracts::CoordContextSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        reducer: Projections::CoordContextReducer.new,
        state_loader: Projections::CoordContextStateLoader.new,
        scope_roots_builder: ProjectionScopeRootsBuilder.new,
        contexts: Repositories::CoordContexts.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @reducer = reducer
        @state_loader = state_loader
        @scope_roots_builder = scope_roots_builder
        @contexts = contexts
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        verify_stream_identity!(event, payload)
        identity = ProjectionEventIdentity.from_event(event)
        processed_at = Time.now.utc

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at:
          )

          record = locked_record(payload.change_set_id, processed_at:)
          rebuild = record.persisted? && record.projection_version != PROJECTION.version
          state = rebuild ? Projections::CoordContextStateV1.initial : load_state(record)
          positions = rebuild ? [ identity.barrier ] : update_source_positions(record, identity.barrier)
          updated = @reducer.apply(state, payload)

          record.assign_attributes(
            projection_version: PROJECTION.version,
            document: updated.to_h,
            source_positions: positions.map(&:to_h),
            last_processed_at: processed_at
          )
          record.save!
          @contexts.store_attempt_event(event:, payload:)
          persist_scope_roots(@scope_roots_builder.call(payload))
        end

        nil
      end

      private

      def verify_stream_identity!(event, payload)
        expected_attempt_id =
          case payload
          when Coordinator::Write::Events::AttemptAuthorizedV1,
               Coordinator::Write::Events::AttemptStartedV1,
               Coordinator::Write::Events::AttemptAbandonedV2,
               Coordinator::Write::Events::WriteSetReservedV2,
               Coordinator::Write::Events::WriteSetExpandedV2,
               Coordinator::Write::Events::WriteSetRenewedV2,
               Coordinator::Write::Events::WriteSetReleasedV2,
               Coordinator::Write::Events::CandidateAttachedToAttemptV1,
               Coordinator::Write::Events::AttemptCompletedV1
            payload.attempt_id
          end
        return unless expected_attempt_id
        return if event.stream.stream_id == expected_attempt_id

        raise InvalidProjectionSource, "Attempt identity does not match its source stream"
      end

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def locked_record(change_set_id, processed_at:)
        record = Coordinator::Read::CoordContext.lock.find_by(change_set_id:)
        return record if record

        Coordinator::Read::CoordContext.new(
          change_set_id:,
          projection_version: PROJECTION.version,
          document: Projections::CoordContextStateV1.initial.to_h,
          source_positions: [],
          last_processed_at: processed_at
        )
      end

      def load_state(record)
        return Projections::CoordContextStateV1.initial if record.new_record?

        @state_loader.call(record.document)
      end

      def update_source_positions(record, barrier)
        positions = record.source_positions.map do |position|
          ProjectionBarrier.new(deep_symbolize(position))
        end
        index = positions.index do |position|
          [ position.stream_context, position.stream_name, position.stream_id ] ==
            [ barrier.stream_context, barrier.stream_name, barrier.stream_id ]
        end

        if index && positions.fetch(index).stream_revision > barrier.stream_revision
          raise ProjectionStateError, "source stream revision moved backwards"
        end

        positions = if index
          positions.each_with_index.map { |position, offset| offset == index ? barrier : position }
        else
          positions + [ barrier ]
        end

        positions.sort_by { [ _1.stream_context, _1.stream_name, _1.stream_id ] }.freeze
      end

      def persist_scope_roots(roots)
        roots.each do |root|
          record = Coordinator::Read::CoordContextScope.find_or_initialize_by(
            scope_kind: root.scope_kind,
            scope_id: root.scope_id
          )
          if record.persisted? && record.change_set_id != root.change_set_id
            raise ProjectionStateError, "projection scope root changed ChangeSet"
          end

          record.change_set_id = root.change_set_id
          record.save!
        end
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_sym, deep_symbolize(nested) ] }
        when Array
          value.map { deep_symbolize(_1) }
        else
          value
        end
      end
    end
  end
end
