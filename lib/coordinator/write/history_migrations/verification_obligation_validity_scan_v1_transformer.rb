# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class VerificationObligationValidityScanV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:)
        @context_resolver = context_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        if source_payload.is_a?(Events::VerificationObligationValidityScanStartedV1)
          context = @context_resolver.from_started(
            migration_id:,
            source_config_name:,
            source_upper_position:,
            source_event:,
            source_started: source_payload
          )
          return context if context.failure?

          return Success(started_facts(context.value!, source_event))
        end

        context = @context_resolver.from_stream(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:
        )
        return context if context.failure?

        case source_payload
        when Events::VerificationObligationValidityScanProgressedV1
          transform_progressed(
            migration_id:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            context: context.value!
          )
        when Events::VerificationObligationValidityScanCompletedV1
          transform_completed(
            migration_id:,
            source_upper_position:,
            source_event:,
            source: source_payload,
            context: context.value!
          )
        else
          Failure(inconsistent(source_event, "unsupported validity-scan source contract"))
        end
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def started_facts(context, source_event)
        source = context.source_started
        [
          fact(
            context:,
            event: Events::VerificationObligationValidityScanStartedV2.new(
              scan_id: context.scan_id,
              change_set_id: context.change_set_id,
              from_position: source.from_position,
              to_position: source.to_position,
              page_size: source.page_size
            ),
            markers: context.start_markers,
            step_name: "start-verification-obligation-validity-scan",
            metadata_extension: actor_metadata(source_event, policy_version: source.rule_version)
          ),
          fact(
            context:,
            event: Events::VerificationObligationValidityScanSourceLinkedV1.new(
              scan_id: context.scan_id,
              role: "superseding_partition",
              source: context.superseding_partition_event
            ),
            markers: context.start_markers + [ "source-role:superseding_partition" ],
            step_name: "link-verification-obligation-validity-scan-superseding-partition",
            metadata_extension: actor_metadata(source_event)
          )
        ].freeze
      end

      def transform_progressed(migration_id:, source_upper_position:, source_event:, source:, context:)
        valid = validate_common(source_event, source, context)
        return valid if valid.failure?

        checkpoint = validate_checkpoint(
          migration_id:,
          source_upper_position:,
          source_event:,
          source:,
          context:,
          terminal: false
        )
        return checkpoint if checkpoint.failure?

        Success([
          fact(
            context:,
            event: Events::VerificationObligationValidityScanProgressedV2.new(
              scan_id: context.scan_id,
              page_number: source.page_number,
              next_from_position: source.next_from_position,
              change_set_id: context.change_set_id,
              page_size: source.page_size
            ),
            markers: context.markers,
            step_name: "progress-verification-obligation-validity-scan",
            metadata_extension: actor_metadata(source_event, policy_version: source.rule_version)
          )
        ])
      end

      def transform_completed(migration_id:, source_upper_position:, source_event:, source:, context:)
        valid = validate_common(source_event, source, context)
        return valid if valid.failure?

        checkpoint = validate_checkpoint(
          migration_id:,
          source_upper_position:,
          source_event:,
          source:,
          context:,
          terminal: true
        )
        return checkpoint if checkpoint.failure?

        Success([
          fact(
            context:,
            event: Events::VerificationObligationValidityScanCompletedV2.new(scan_id: context.scan_id),
            markers: context.markers,
            step_name: "complete-verification-obligation-validity-scan",
            metadata_extension: actor_metadata(source_event)
          )
        ])
      end

      def validate_common(source_event, source, context)
        started = context.source_started
        valid = source.scan_id == started.scan_id &&
                source.change_set_id == started.change_set_id &&
                source.superseding_partition_event == started.superseding_partition_event &&
                source.started_event == context.source_started_reference &&
                source.page_size == started.page_size &&
                source.rule_version == started.rule_version
        return Success() if valid

        Failure(inconsistent(source_event, "scan checkpoint disagrees with its start fact"))
      end

      def validate_checkpoint(
        migration_id:,
        source_upper_position:,
        source_event:,
        source:,
        context:,
        terminal:
      )
        loaded = @context_resolver.load_reference(
          source_event:,
          source_upper_position:,
          source_reference: source.previous_checkpoint
        )
        return loaded if loaded.failure?

        payload = loaded.value!.last
        expected_page, expected_from, event_type, step_name = checkpoint_expectation(payload, context)
        valid = expected_page &&
                source.previous_from_position == expected_from &&
                (terminal ? source.page_count : source.page_number) == expected_page
        return Failure(inconsistent(source_event, "scan checkpoint chronology is inconsistent")) unless valid

        @context_resolver.target_reference(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference: source.previous_checkpoint,
          target_stream: context.target_stream,
          target_event_type: event_type,
          target_step_name: step_name
        )
      end

      def checkpoint_expectation(payload, context)
        case payload
        when Events::VerificationObligationValidityScanStartedV1
          return unless payload == context.source_started

          [ 1, payload.from_position, "VerificationObligationValidityScanStarted",
            "start-verification-obligation-validity-scan" ]
        when Events::VerificationObligationValidityScanProgressedV1
          [ payload.page_number + 1, payload.next_from_position,
            "VerificationObligationValidityScanProgressed",
            "progress-verification-obligation-validity-scan" ]
        end
      end

      def fact(context:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream: context.target_stream,
          event:,
          markers: markers.uniq.freeze,
          step_name:,
          metadata_extension:
        )
      end

      def actor_metadata(source_event, policy_version: nil)
        MigrationMetadataExtensionV1.new(
          attributed_actor: Commands::Actor.new(
            kind: source_event.metadata.fetch("actor_kind"),
            id: source_event.metadata.fetch("actor_id")
          ),
          policy_version:
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Verification-obligation validity scan source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end
