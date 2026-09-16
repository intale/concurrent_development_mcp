# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceImpactScanContextResolver
      include Dry::Monads[:result]

      SOURCE_TYPES = {
        "AgentChoiceImpactScanStarted" => Events::AgentChoiceImpactScanStartedV1,
        "AgentChoiceImpactScanProgressed" => Events::AgentChoiceImpactScanProgressedV1,
        "AgentChoiceImpactScanSkipped" => Events::AgentChoiceImpactScanSkippedV1,
        "AgentChoiceImpactScanCompleted" => Events::AgentChoiceImpactScanCompletedV1
      }.freeze
      LATEST = LatestEventReadCriteria.new(event_types: SOURCE_TYPES.keys.freeze)

      def initialize(
        event_store:,
        stream_identity_allocator:,
        decision_change_transformer:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @decision_change_transformer = decision_change_transformer
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        valid_envelope!(source_event, source_payload, source_upper_position:)
        started_event, started = started_source(
          source_event,
          source_payload,
          source_upper_position:
        )
        validate_history!(
          source_event,
          source_payload,
          started_event:,
          started:,
          source_upper_position:
        )

        decision_change = @decision_change_transformer.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          evidence: source_payload.is_a?(Events::AgentChoiceImpactScanSkippedV1) ?
            source_payload.decision_change : started.decision_change
        )
        return decision_change if decision_change.failure?

        allocation = @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "AgentGovernance",
          target_stream_name: "AgentChoiceImpactScan",
          identity_role: "agent-choice-impact-scan"
        )
        return allocation if allocation.failure?

        target_stream = allocation.value!.target_stream
        Success(
          AgentChoiceImpactScanContextV1.new(
            target_stream:,
            scan_id: target_stream.stream_id,
            decision_change: decision_change.value!,
            from_position: started&.from_position,
            to_position: started&.to_position,
            page_size: started&.page_size
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def valid_envelope!(source_event, source_payload, source_upper_position:)
        expected_class = SOURCE_TYPES.fetch(source_event.type)
        valid = source_payload.is_a?(expected_class) &&
                source_event.metadata.fetch("schema_version") == 1 &&
                source_event.global_position <= source_upper_position &&
                source_event.stream.context == "AgentGovernance" &&
                source_event.stream.stream_name == "AgentChoiceImpactScan" &&
                source_event.stream.stream_id == source_payload.scan_id &&
                source_event.metadata.fetch("policy_version") == source_payload.policy_version &&
                source_event.metadata.fetch("actor_kind") == "system" &&
                source_event.metadata.fetch("actor_id") == "agent-choice-decision-impact"
        raise ArgumentError, "scan identity or metadata does not match its source stream" unless valid

        initial = source_payload.is_a?(Events::AgentChoiceImpactScanStartedV1) ||
                  source_payload.is_a?(Events::AgentChoiceImpactScanSkippedV1)
        valid_revision = initial ? source_event.stream_revision.zero? : source_event.stream_revision.positive?
        raise ArgumentError, "scan lifecycle revision is invalid" unless valid_revision
      end

      def started_source(source_event, source_payload, source_upper_position:)
        return [ source_event, source_payload ] if source_payload.is_a?(Events::AgentChoiceImpactScanStartedV1)
        return [ nil, nil ] if source_payload.is_a?(Events::AgentChoiceImpactScanSkippedV1)

        event = exact_event(source_payload.started_event, source_upper_position:)
        payload = event && load(event)
        valid = payload.is_a?(Events::AgentChoiceImpactScanStartedV1) &&
                event.stream_revision.zero? &&
                same_stream?(event, source_event) &&
                payload.scan_id == source_payload.scan_id
        raise ArgumentError, "started scan reference is invalid" unless valid

        [ event, payload ]
      end

      def validate_history!(source_event, source_payload, started_event:, started:, source_upper_position:)
        validate_terminal!(source_event, source_payload, source_upper_position:)
        if source_payload.is_a?(Events::AgentChoiceImpactScanSkippedV1)
          validate_skip!(source_payload)
          return
        end

        validate_started!(started_event, started)
        return if source_payload.is_a?(Events::AgentChoiceImpactScanStartedV1)

        validate_checkpoint!(source_event, source_payload, started, source_upper_position:)
      end

      def validate_terminal!(source_event, source_payload, source_upper_position:)
        latest = @event_store.read_latest(stream_for(source_event), LATEST)
        valid = latest && latest.global_position <= source_upper_position &&
                same_stream?(latest, source_event)
        if source_payload.is_a?(Events::AgentChoiceImpactScanSkippedV1)
          valid &&= latest.id == source_event.id && latest.type == "AgentChoiceImpactScanSkipped"
        else
          valid &&= latest.type == "AgentChoiceImpactScanCompleted"
        end
        raise ArgumentError, "frozen scan history is not terminal" unless valid
      end

      def validate_skip!(source)
        expected = skip_reason(source.decision_change.retroactivity)
        raise ArgumentError, "skipped scan reason is inconsistent" unless expected == source.reason
      end

      def validate_started!(started_event, started)
        valid = started &&
                started_event &&
                started.from_position.zero? &&
                started.to_position == started.decision_change.source_global_position &&
                skip_reason(started.decision_change.retroactivity).nil?
        raise ArgumentError, "started scan range or Decision policy is inconsistent" unless valid
      end

      def validate_checkpoint!(source_event, source, started, source_upper_position:)
        previous_event = exact_event(source.previous_checkpoint, source_upper_position:)
        previous = previous_event && load(previous_event)
        valid = previous_event &&
                same_stream?(previous_event, source_event) &&
                previous_event.stream_revision == source_event.stream_revision - 1 &&
                source.started_event.stream_revision.zero? &&
                source.policy_version == started.policy_version
        raise ArgumentError, "previous scan checkpoint is invalid" unless valid

        previous_from, previous_page_count, previous_total = checkpoint_values(previous, source.started_event)
        valid_counts = source.previous_from_position == previous_from &&
                       source.total_choice_count == previous_total + source.page_choice_count
        if source.is_a?(Events::AgentChoiceImpactScanProgressedV1)
          valid_counts &&= source.page_number == previous_page_count + 1 &&
                          source.next_from_position.between?(previous_from, started.to_position)
        else
          valid_counts &&= source.page_count == previous_page_count + 1 &&
                          source.final_from_position.between?(previous_from, started.to_position + 1)
        end
        raise ArgumentError, "scan checkpoint counters or bounds are inconsistent" unless valid_counts
      end

      def checkpoint_values(previous, started_reference)
        case previous
        when Events::AgentChoiceImpactScanStartedV1
          [ previous.from_position, 0, 0 ]
        when Events::AgentChoiceImpactScanProgressedV1
          unless previous.started_event == started_reference
            raise ArgumentError, "scan checkpoint points to another start"
          end

          [ previous.next_from_position, previous.page_number, previous.total_choice_count ]
        else
          raise ArgumentError, "scan checkpoint is not running"
        end
      end

      def skip_reason(retroactivity)
        case retroactivity
        when "active_attempts" then nil
        when "future_only" then "future_only"
        when "all_unverified_candidates", "all_unmerged_candidates" then "candidate_scope"
        when "all_artifacts" then "artifact_scope"
        end
      end

      def exact_event(reference, source_upper_position:)
        event = @event_store.read_at(stream_for(reference), reference.stream_revision)
        return unless event && event.id == reference.event_id && event.type == reference.type
        return unless event.global_position <= source_upper_position

        event
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(value)
        if value.is_a?(PgEventstore::Event)
          return StreamReference.new(
            context: value.stream.context,
            stream_name: value.stream.stream_name,
            stream_id: value.stream.stream_id
          )
        end

        StreamReference.new(
          context: value.stream_context,
          stream_name: value.stream_name,
          stream_id: value.stream_id
        )
      end

      def same_stream?(left, right)
        left.stream.context == right.stream.context &&
          left.stream.stream_name == right.stream.stream_name &&
          left.stream.stream_id == right.stream.stream_id
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "AgentChoice impact scan source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
