# frozen_string_literal: true

module Coordinator::Processes
  module CandidateObligations
    class CommandBuilder
      ACTOR = Coordinator::Write::Commands::Actor.new(
        kind: "system",
        id: "candidate-impact-obligation-policy"
      )
      REGISTRY_RULE_VERSION = "candidate-impact-registry-sweep/v1"
      PAIR_RULE_VERSION = "candidate-impact-pair-scan/v1"
      OBLIGATION_RULE_VERSION = "candidate-compatibility-obligation/v1"
      INDEX_POLICY_VERSION = "candidate-impact-exact-index/v2"
      PAGE_SIZE = 50

      def initialize(
        event_store:,
        process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
        reference_builder: EventReferenceBuilder.new
      )
        @process_step_planner = process_step_planner
        @reference_builder = reference_builder
      end

      def registry_start(trigger:, source:)
        process_step = plan(
          source_event: source.event,
          step_name: "start-registry-sweep",
          subject_kind: "candidate-policy-partition",
          subject_id: trigger.partition_event.event_id,
          rule_version: REGISTRY_RULE_VERSION,
          allocate_target_entity: true
        )
        command = Coordinator::Write::Commands::StartCandidateImpactRegistrySweep.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          scan_id: process_step.target_entity_id!,
          change_set_id: trigger.change_set_id,
          policy_partition_event: trigger.partition_event,
          policy_head: trigger.head,
          from_revision: 0,
          page_size: PAGE_SIZE,
          rule_version: REGISTRY_RULE_VERSION
        )
        Coordinator::Write::CandidateImpactRegistrySweepInvocation.new(
          command:,
          source_event: source.event,
          source_reference: source.reference,
          caused_by: process_step.event
        )
      end

      def pair_start(registration:, direction:, trigger:, caused_by:)
        registration_reference = @reference_builder.call(registration)
        process_step = plan(
          source_event: caused_by.event,
          step_name: "start-#{direction}-pair-scan",
          subject_kind: "candidate-impact-registration",
          subject_id: registration_reference.event_id,
          rule_version: PAIR_RULE_VERSION,
          allocate_target_entity: true
        )
        command = Coordinator::Write::Commands::StartCandidateImpactPairScan.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          scan_id: process_step.target_entity_id!,
          change_set_id: trigger.change_set_id,
          source_registration: registration_reference,
          direction:,
          policy_partition_event: trigger.partition_event,
          policy_head: trigger.head,
          from_revision: 0,
          to_revision: registration_reference.stream_revision - 1,
          page_size: PAGE_SIZE,
          index_policy_version: INDEX_POLICY_VERSION,
          rule_version: PAIR_RULE_VERSION
        )
        Coordinator::Write::CandidateImpactPairScanInvocation.new(
          command:,
          source_event: caused_by.event,
          source_reference: caused_by.reference,
          caused_by: process_step.event
        )
      end

      def registry_progress(checkpoint:, page:)
        state = checkpoint.state
        process_step = plan(
          source_event: checkpoint.event,
          step_name: "progress-registry-sweep",
          subject_kind: "candidate-impact-registry-sweep",
          subject_id: state.scan_id,
          rule_version: state.rule_version,
          allocate_target_entity: false
        )
        command = Coordinator::Write::Commands::ProgressCandidateImpactRegistrySweep.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          scan_id: state.scan_id,
          change_set_id: state.change_set_id,
          policy_partition_event: state.policy_partition_event,
          policy_head: state.policy_head,
          expected_checkpoint: checkpoint.reference,
          previous_from_revision: state.from_revision,
          last_processed_revision: page.last_processed_revision,
          page_registration_count: page.registrations.length,
          has_more: page.has_more,
          page_size: state.page_size,
          rule_version: state.rule_version
        )
        Coordinator::Write::CandidateImpactRegistrySweepProgressInvocation.new(
          command:,
          checkpoint_event: checkpoint.event,
          checkpoint_reference: checkpoint.reference,
          caused_by: process_step.event
        )
      end

      def pair_progress(checkpoint:, page:)
        state = checkpoint.state
        process_step = plan(
          source_event: checkpoint.event,
          step_name: "progress-#{state.direction}-pair-scan",
          subject_kind: "candidate-impact-pair-scan",
          subject_id: state.scan_id,
          rule_version: state.rule_version,
          allocate_target_entity: false
        )
        command = Coordinator::Write::Commands::ProgressCandidateImpactPairScan.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          scan_id: state.scan_id,
          change_set_id: state.change_set_id,
          source_registration: state.source_registration,
          direction: state.direction,
          policy_partition_event: state.policy_partition_event,
          policy_head: state.policy_head,
          expected_checkpoint: checkpoint.reference,
          previous_from_revision: state.from_revision,
          last_processed_revision: page.last_processed_revision,
          page_registration_count: page.registrations.length,
          has_more: page.has_more,
          page_size: state.page_size,
          index_policy_version: state.index_policy_version,
          rule_version: state.rule_version
        )
        Coordinator::Write::CandidateImpactPairScanProgressInvocation.new(
          command:,
          checkpoint_event: checkpoint.event,
          checkpoint_reference: checkpoint.reference,
          caused_by: process_step.event
        )
      end

      def obligation(checkpoint:, target_registration:)
        state = checkpoint.state
        target_reference = @reference_builder.call(target_registration)
        source_reference, destination_reference = ordered_pair(
          state.source_registration,
          target_reference,
          state.direction
        )
        process_step = plan(
          source_event: checkpoint.event,
          step_name: "create-compatibility-obligation",
          subject_kind: "candidate-registration-pair",
          subject_id: "#{source_reference.event_id}:#{destination_reference.event_id}",
          rule_version: OBLIGATION_RULE_VERSION,
          allocate_target_entity: true
        )
        command = Coordinator::Write::Commands::CreateCandidateCompatibilityObligation.new(
          command_id: process_step.target_command_id,
          actor: ACTOR,
          obligation_id: process_step.target_entity_id!,
          source_registration: source_reference,
          target_registration: destination_reference,
          policy_partition_event: state.policy_partition_event,
          policy_head: state.policy_head,
          rule_version: OBLIGATION_RULE_VERSION
        )
        Coordinator::Write::CandidateCompatibilityObligationInvocation.new(
          command:,
          caused_by: process_step.event,
          caused_by_reference: process_step.reference
        )
      end

      private

      def ordered_pair(source, target, direction)
        direction == "outgoing" ? [ source, target ] : [ target, source ]
      end

      def plan(source_event:, step_name:, subject_kind:, subject_id:, rule_version:, allocate_target_entity:)
        @process_step_planner.call(
          source_event:,
          process_name: "candidate-impact-obligation-policy",
          step_name:,
          subject_kind:,
          subject_id:,
          rule_version:,
          allocate_target_entity:
        )
      end
    end
  end
end
