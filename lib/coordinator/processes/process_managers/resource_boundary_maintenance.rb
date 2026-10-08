# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class ResourceBoundaryMaintenance
      class Rejected < StandardError; end

      class SourceContract < Dry::Validation::Contract
        EVENT_TYPES = Coordinator::Write::EventQueries::WORK_INTENTION_LIFECYCLE_EVENT_TYPES

        params do
          required(:event).value(Types.Instance(PgEventstore::Event))
        end

        rule(:event) do
          key.failure("must be a persisted event") unless value.stream_revision && value.global_position
          key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
          unless EVENT_TYPES.include?(value.type) && value.metadata["schema_version"] == 1
            key.failure("must be a ResourceWorkIntention lifecycle event at schema 1")
          end
          stream = value.stream
          unless stream&.context == "DevelopmentCoordination" &&
                 stream.stream_name == "ResourceWorkIntention" &&
                 stream.stream_id == value.data["intention_id"]
            key.failure("must belong to its ResourceWorkIntention stream")
          end
          key.failure("must carry command provenance") unless Types::IDENTIFIER_PATTERN.match?(value.metadata["command_id"].to_s)
          key.failure("must carry a trace correlation ID") unless Types::UUID_V7_PATTERN.match?(value.correlation_id.to_s)
          boundary_prefix = "#{Coordinator::Shared::ResourceMarkerCodec::BOUNDARY_PREFIX}|"
          key.failure("must carry a resource boundary marker") unless value.markers.any? { _1.start_with?(boundary_prefix) }
        end
      end

      SYSTEM_ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "resource-boundary-maintenance-v3"
      )
      ACTIVE_SOURCE_EVENT_TYPES = %w[ResourceWorkIntentionDeclared ResourceWorkIntentionRenewed].freeze

      def initialize(
        event_store:,
        contract: SourceContract.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        intention_loader: Coordinator::Write::WorkIntentionLoader.new(event_store:),
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        operation: Coordinator::Write::Operations::ExecuteRollResourceBoundaryEpoch.new(event_store:)
      )
        @contract = contract
        @schema_registry = schema_registry
        @intention_loader = intention_loader
        @process_step_planner = process_step_planner
        @operation = operation
      end

      def call(event)
        validated = @contract.call(event:)
        raise Rejected, validated.errors.to_h.inspect if validated.failure?

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        state = @intention_loader.call(payload.intention_id).state
        raise Rejected, "ResourceWorkIntention history is missing its declaration" if state.absent?

        # At this immutable cutoff the source itself proves a nonempty boundary.
        # Later withdrawal or expiry cannot make that historical cutoff empty.
        return nil if ACTIVE_SOURCE_EVENT_TYPES.include?(event.type) &&
          Time.iso8601(payload.expires_at) > event.created_at

        boundary_markers(event).each_with_index do |marker, boundary_index|
          process_step = @process_step_planner.call(
            source_event: event,
            process_name: "resource-boundary-maintenance",
            step_name: "roll-resource-boundary-epoch",
            subject_kind: "boundary-index",
            subject_id: boundary_index.to_s,
            rule_version: "resource-boundary-rollover/v3",
            allocate_target_entity: false
          )
          result = @operation.call_command(
            command(
              event:,
              repository_id: state.repository_id,
              marker:,
              command_id: process_step.target_command_id
            ),
            caused_by: process_step.event
          )
          next if result.success?

          @process_step_planner.record_dispatch_failure(process_step:, failure: result.failure)
        end
        nil
      rescue Dry::Struct::Error,
             Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise Rejected, error.message
      end

      private

      def boundary_markers(event)
        event.markers.grep(/\A#{Regexp.escape(Coordinator::Shared::ResourceMarkerCodec::BOUNDARY_PREFIX)}\|/)
          .uniq
          .sort_by(&:b)
      end

      def command(event:, repository_id:, marker:, command_id:)
        Coordinator::Write::Commands::RollResourceBoundaryEpoch.new(
          command_id:,
          actor: SYSTEM_ACTOR,
          repository_id:,
          boundary_marker: marker,
          source_event_id: event.id,
          source_global_position: event.global_position,
          source_created_at: event.created_at.utc.iso8601(6)
        )
      end
    end
  end
end
