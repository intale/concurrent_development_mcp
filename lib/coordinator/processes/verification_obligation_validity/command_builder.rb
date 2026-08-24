# frozen_string_literal: true

module Coordinator::Processes
  module VerificationObligationValidity
    class CommandBuilder
      ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "verification-obligation-validity-policy"
      )
      RULE_VERSION = "verification-obligation-validity/v1"
      PAGE_SIZE = 50

      def initialize(
        scan_identity_builder: Coordinator::Write::VerificationObligationValidityScans::IdentityBuilder.new,
        invalidation_identity_builder: Coordinator::Write::VerificationObligationInvalidations::IdentityBuilder.new
      )
        @scan_identity_builder = scan_identity_builder
        @invalidation_identity_builder = invalidation_identity_builder
      end

      def start(source)
        change_set_id = source.payload.partition.anchor_id
        scan_id = @scan_identity_builder.scan(
          superseding_partition_event: source.reference,
          rule_version: RULE_VERSION
        )
        command = Coordinator::Write::Commands::StartVerificationObligationValidityScan.new(
          command_id: scan_id,
          actor: ACTOR,
          scan_id:,
          change_set_id:,
          superseding_partition_event: source.reference,
          source_global_position: source.event.global_position,
          rule_version: RULE_VERSION
        )
        Coordinator::Write::VerificationObligationValidityScanInvocation.new(
          command:,
          source_event: source.event,
          source_reference: source.reference
        )
      end

      def progress(checkpoint:, page:)
        command_id = @scan_identity_builder.progress(
          checkpoint_event: checkpoint.reference,
          rule_version: checkpoint.rule_version
        )
        command = Coordinator::Write::Commands::ProgressVerificationObligationValidityScan.new(
          command_id:,
          actor: ACTOR,
          scan_id: checkpoint.scan_id,
          change_set_id: checkpoint.change_set_id,
          superseding_partition_event: checkpoint.superseding_partition_event,
          expected_checkpoint: checkpoint.reference,
          previous_from_position: checkpoint.from_position,
          last_processed_position: page.last_processed_position,
          page_obligation_count: page.obligations.length,
          has_more: page.has_more,
          page_size: PAGE_SIZE,
          rule_version: checkpoint.rule_version
        )
        Coordinator::Write::VerificationObligationValidityScanProgressInvocation.new(
          command:,
          checkpoint_event: checkpoint.event,
          checkpoint_reference: checkpoint.reference
        )
      end

      def invalidation(obligation_event:, superseding_partition_event:, caused_by_event:, caused_by_reference:)
        obligation_reference = reference(obligation_event)
        command_id = @invalidation_identity_builder.call(
          obligation_event: obligation_reference,
          superseding_partition_event:,
          rule_version: RULE_VERSION
        )
        command = Coordinator::Write::Commands::InvalidateVerificationObligation.new(
          command_id:,
          actor: ACTOR,
          obligation_id: obligation_reference.stream_id,
          obligation_event: obligation_reference,
          superseding_partition_event:,
          rule_version: RULE_VERSION
        )
        Coordinator::Write::VerificationObligationInvalidationInvocation.new(
          command:,
          caused_by_event:,
          caused_by_reference:
        )
      end

      private

      def reference(event)
        Coordinator::Write::EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end
