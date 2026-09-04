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
        event_store:,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:)
      )
        @process_step_planner = process_step_planner
      end

      def start(source)
        change_set_id = change_set_id(source.payload)
        process_step = plan(
          source_event: source.event,
          step_name: "start-validity-scan",
          subject_kind: "candidate-policy-partition",
          subject_id: source.reference.event_id,
          allocate_target_entity: true
        )
        command = Coordinator::Write::Commands::StartVerificationObligationValidityScan.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          scan_id: process_step.target_entity_id!,
          change_set_id:,
          superseding_partition_event: source.reference,
          source_global_position: source.event.global_position,
          rule_version: RULE_VERSION
        )
        Coordinator::Write::VerificationObligationValidityScanInvocation.new(
          command:,
          source_event: source.event,
          source_reference: source.reference,
          caused_by: process_step.event
        )
      end

      def progress(checkpoint:, page:)
        process_step = plan(
          source_event: checkpoint.event,
          step_name: "progress-validity-scan",
          subject_kind: "verification-obligation-validity-scan",
          subject_id: checkpoint.scan_id,
          allocate_target_entity: false
        )
        command = Coordinator::Write::Commands::ProgressVerificationObligationValidityScan.new(
          command_id: process_step.target_command_id,
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
          checkpoint_reference: checkpoint.reference,
          caused_by: process_step.event
        )
      end

      def invalidation(obligation_event:, superseding_partition_event:, caused_by_event:, caused_by_reference:)
        obligation_reference = reference(obligation_event)
        process_step = plan(
          source_event: caused_by_event,
          step_name: "invalidate-obligation",
          subject_kind: "obligation-policy-pair",
          subject_id: "#{obligation_reference.event_id}:#{superseding_partition_event.event_id}",
          allocate_target_entity: false
        )
        command = Coordinator::Write::Commands::InvalidateVerificationObligation.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          obligation_id: obligation_reference.stream_id,
          obligation_event: obligation_reference,
          superseding_partition_event:,
          rule_version: RULE_VERSION
        )
        Coordinator::Write::VerificationObligationInvalidationInvocation.new(
          command:,
          caused_by_event: process_step.event,
          caused_by_reference: process_step.reference
        )
      end

      private

      def change_set_id(payload)
        return payload.partition.anchor_id if payload.is_a?(Coordinator::Write::Events::DecisionPartitionAdvancedV1)

        payload.partition_id.delete_prefix("changeset:").delete_suffix(":candidate")
      end

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

      def plan(source_event:, step_name:, subject_kind:, subject_id:, allocate_target_entity:)
        @process_step_planner.call(
          source_event:,
          process_name: "verification-obligation-validity-policy",
          step_name:,
          subject_kind:,
          subject_id:,
          rule_version: RULE_VERSION,
          allocate_target_entity:
        )
      end
    end
  end
end
