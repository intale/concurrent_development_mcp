# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CandidateImpactScanV1Transformer
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
        facts =
          case source_payload
          when Events::CandidateImpactPairScanStartedV1
            pair_started(context, source_event, source_payload)
          when Events::CandidateImpactPairScanProgressedV1
            pair_progressed(context, source_event, source_payload)
          when Events::CandidateImpactPairScanSkippedV1
            pair_skipped(context, source_event, source_payload)
          when Events::CandidateImpactPairScanCompletedV1
            pair_completed(context, source_event, source_payload)
          when Events::CandidateImpactRegistrySweepStartedV1
            registry_started(context, source_event, source_payload)
          when Events::CandidateImpactRegistrySweepProgressedV1
            registry_progressed(context, source_event, source_payload)
          when Events::CandidateImpactRegistrySweepSkippedV1
            registry_skipped(context, source_event, source_payload)
          when Events::CandidateImpactRegistrySweepCompletedV1
            registry_completed(context, source_event)
          end
        Success(facts)
      end

      private

      def pair_started(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactPairScanStartedV2.new(
              scan_id: context.scan_id,
              change_set_id: context.change_set_id,
              direction: source.direction,
              markers: context.routing_markers,
              from_revision: source.from_revision,
              to_revision: source.to_revision,
              page_size: source.page_size
            ),
            markers: pair_start_markers(context, source.direction),
            step_name: "start-candidate-impact-pair-scan",
            metadata_extension: pair_metadata(source_event, source)
          )
        ] + pair_source_links(context, source_event, source.direction)
      end

      def pair_skipped(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactPairScanSkippedV2.new(
              scan_id: context.scan_id,
              reason: source.reason
            ),
            markers: pair_start_markers(context, source.direction),
            step_name: "skip-candidate-impact-pair-scan",
            metadata_extension: pair_metadata(source_event, source)
          )
        ] + pair_source_links(context, source_event, source.direction)
      end

      def pair_progressed(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactPairScanProgressedV2.new(
              scan_id: context.scan_id,
              page_number: source.page_number,
              next_from_revision: source.next_from_revision,
              change_set_id: context.change_set_id,
              direction: source.direction,
              markers: context.routing_markers,
              to_revision: source.to_revision,
              page_size: source.page_size
            ),
            markers: pair_progress_markers(context, source.direction),
            step_name: "progress-candidate-impact-pair-scan",
            metadata_extension: pair_metadata(source_event, source)
          )
        ]
      end

      def pair_completed(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactPairScanCompletedV2.new(scan_id: context.scan_id),
            markers: pair_progress_markers(context, source.direction),
            step_name: "complete-candidate-impact-pair-scan",
            metadata_extension: pair_metadata(source_event, nil)
          )
        ]
      end

      def registry_started(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactRegistrySweepStartedV2.new(
              scan_id: context.scan_id,
              change_set_id: context.change_set_id,
              from_revision: source.from_revision,
              to_revision: source.to_revision,
              page_size: source.page_size
            ),
            markers: registry_start_markers(context),
            step_name: "start-candidate-impact-registry-sweep",
            metadata_extension: policy_metadata(source_event, source.rule_version)
          )
        ] + registry_source_links(context, source_event)
      end

      def registry_skipped(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactRegistrySweepSkippedV2.new(
              scan_id: context.scan_id,
              reason: source.reason
            ),
            markers: registry_start_markers(context),
            step_name: "skip-candidate-impact-registry-sweep",
            metadata_extension: policy_metadata(source_event, source.rule_version)
          )
        ] + registry_source_links(context, source_event)
      end

      def registry_progressed(context, source_event, source)
        [
          fact(
            context:,
            event: Events::CandidateImpactRegistrySweepProgressedV2.new(
              scan_id: context.scan_id,
              page_number: source.page_number,
              next_from_revision: source.next_from_revision,
              change_set_id: context.change_set_id,
              to_revision: source.to_revision,
              page_size: source.page_size
            ),
            markers: registry_progress_markers(context),
            step_name: "progress-candidate-impact-registry-sweep",
            metadata_extension: policy_metadata(source_event, source.rule_version)
          )
        ]
      end

      def registry_completed(context, source_event)
        [
          fact(
            context:,
            event: Events::CandidateImpactRegistrySweepCompletedV2.new(scan_id: context.scan_id),
            markers: registry_progress_markers(context),
            step_name: "complete-candidate-impact-registry-sweep",
            metadata_extension: actor_metadata(source_event)
          )
        ]
      end

      def pair_source_links(context, source_event, direction)
        {
          "source_registration" => context.source_registration,
          "policy_partition" => context.policy_partition,
          "policy_head" => context.policy_head
        }.map do |role, source|
          fact(
            context:,
            event: Events::CandidateImpactPairScanSourceLinkedV1.new(
              scan_id: context.scan_id,
              role:,
              source:
            ),
            markers: pair_start_markers(context, direction) + [ "source-role:#{role}" ],
            step_name: "link-candidate-impact-pair-scan-#{role.tr('_', '-')}",
            metadata_extension: actor_metadata(source_event)
          )
        end
      end

      def registry_source_links(context, source_event)
        {
          "policy_partition" => context.policy_partition,
          "policy_head" => context.policy_head
        }.map do |role, source|
          fact(
            context:,
            event: Events::CandidateImpactRegistrySweepSourceLinkedV1.new(
              scan_id: context.scan_id,
              role:,
              source:
            ),
            markers: registry_start_markers(context) + [ "source-role:#{role}" ],
            step_name: "link-candidate-impact-registry-sweep-#{role.tr('_', '-')}",
            metadata_extension: actor_metadata(source_event)
          )
        end
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

      def pair_start_markers(context, direction)
        [
          "candidate-impact-pair-scan:#{context.scan_id}",
          "change-set:#{context.change_set_id}",
          "candidate-impact-direction:#{direction}",
          "source-registration:#{context.source_registration.event_id}",
          "decision:#{context.decision_id}"
        ]
      end

      def pair_progress_markers(context, direction)
        [
          "candidate-impact-pair-scan:#{context.scan_id}",
          "change-set:#{context.change_set_id}",
          "candidate-impact-direction:#{direction}"
        ]
      end

      def registry_start_markers(context)
        [
          "candidate-impact-registry-sweep:#{context.scan_id}",
          "change-set:#{context.change_set_id}",
          "decision:#{context.decision_id}",
          "policy-partition-event:#{context.policy_partition.event_id}"
        ]
      end

      def registry_progress_markers(context)
        [
          "candidate-impact-registry-sweep:#{context.scan_id}",
          "change-set:#{context.change_set_id}"
        ]
      end

      def pair_metadata(source_event, source)
        MigrationMetadataExtensionV1.new(
          attributed_actor: actor_from(source_event),
          policy_version: source&.rule_version,
          index_policy_version: Candidates::ImpactIndexMarkerBuilder::POLICY_VERSION
        )
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
    end
  end
end
