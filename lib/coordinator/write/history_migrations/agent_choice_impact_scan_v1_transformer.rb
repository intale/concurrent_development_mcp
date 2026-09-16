# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class AgentChoiceImpactScanV1Transformer
      include Dry::Monads[:result]

      def initialize(context_resolver:)
        @context_resolver = context_resolver
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        resolved = @context_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          source_payload:
        )
        return resolved if resolved.failure?

        context = resolved.value!
        facts = case source_payload
        when Events::AgentChoiceImpactScanStartedV1
          started(context, source_event, source_payload)
        when Events::AgentChoiceImpactScanProgressedV1
          progressed(context, source_event, source_payload)
        when Events::AgentChoiceImpactScanSkippedV1
          skipped(context, source_event, source_payload)
        when Events::AgentChoiceImpactScanCompletedV1
          completed(context, source_event)
        end
        Success(facts)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def started(context, source_event, source)
        [
          fact(
            context:,
            event: Events::AgentChoiceImpactScanStartedV2.new(
              scan_id: context.scan_id,
              decision_change: context.decision_change,
              from_position: source.from_position,
              to_position: source.to_position,
              page_size: source.page_size
            ),
            markers: start_markers(context),
            step_name: "start-agent-choice-impact-scan",
            metadata_extension: policy_metadata(source_event, source.policy_version)
          ),
          fact(
            context:,
            event: Events::AgentChoiceImpactScanSourceLinkedV1.new(
              scan_id: context.scan_id,
              role: "decision_change",
              source: context.decision_change.source_event
            ),
            markers: start_markers(context) + [ "source-role:decision_change" ],
            step_name: "link-agent-choice-impact-scan-decision-change",
            metadata_extension: actor_metadata(source_event)
          )
        ]
      end

      def skipped(context, source_event, source)
        [
          fact(
            context:,
            event: Events::AgentChoiceImpactScanSkippedV2.new(
              scan_id: context.scan_id,
              reason: source.reason
            ),
            markers: start_markers(context),
            step_name: "skip-agent-choice-impact-scan",
            metadata_extension: policy_metadata(source_event, source.policy_version)
          )
        ]
      end

      def progressed(context, source_event, source)
        [
          fact(
            context:,
            event: Events::AgentChoiceImpactScanProgressedV2.new(
              scan_id: context.scan_id,
              page_number: source.page_number,
              next_from_position: source.next_from_position,
              decision_change: context.decision_change,
              from_position: context.from_position,
              to_position: context.to_position,
              page_size: context.page_size
            ),
            markers: progress_markers(context),
            step_name: "progress-agent-choice-impact-scan",
            metadata_extension: policy_metadata(source_event, source.policy_version)
          )
        ]
      end

      def completed(context, source_event)
        [
          fact(
            context:,
            event: Events::AgentChoiceImpactScanCompletedV2.new(scan_id: context.scan_id),
            markers: progress_markers(context),
            step_name: "complete-agent-choice-impact-scan",
            metadata_extension: actor_metadata(source_event)
          )
        ]
      end

      def fact(context:, event:, markers:, step_name:, metadata_extension:)
        TransformedFactV1.new(
          target_stream: context.target_stream,
          event:,
          markers:,
          step_name:,
          metadata_extension:
        )
      end

      def start_markers(context)
        [
          "impact-scan:#{context.scan_id}",
          "decision:#{context.decision_change.decision_id}",
          "decision-change:#{context.decision_change.source_event.event_id}"
        ]
      end

      def progress_markers(context)
        [ "impact-scan:#{context.scan_id}" ]
      end

      def policy_metadata(source_event, policy_version)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version:
        )
      end

      def actor_metadata(source_event)
        MigrationMetadataExtensionV1.new(attributed_actor: actor_from(source_event))
      end

      def actor_from(source_event)
        Commands::Actor.new(
          kind: source_event.metadata.fetch("actor_kind"),
          id: source_event.metadata.fetch("actor_id")
        )
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
